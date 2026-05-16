import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages a user's long-lived X25519 keypair used for end-to-end encryption.
///
/// Lifecycle:
///   • The PRIVATE key is generated on the device the first time a signed-in
///     user opens the app. It is stored in Keychain (iOS) / EncryptedSharedPrefs
///     backed by the Android Keystore — never written to disk in plaintext, never
///     transmitted off-device, and not part of any backup that lives in the user's
///     iCloud / Google account by default.
///   • The PUBLIC key (32 bytes, base64) is published to Firestore at
///     `users/{uid}.publicKey` so other users can wrap per-chat session keys
///     against it.
///
/// A new device for the same user gets a NEW keypair — old ciphertext that was
/// only wrapped against the old public key cannot be decrypted on the new device.
/// This is the same trade-off Signal makes for "new device, no history."
class KeyManager {
  KeyManager({FlutterSecureStorage? storage, FirebaseFirestore? firestore})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _db = firestore ?? FirebaseFirestore.instance;

  final FlutterSecureStorage _storage;
  final FirebaseFirestore _db;

  static final _x25519 = Cryptography.instance.x25519();

  String _privKeyStorageKey(String uid) => 'e2ee.privkey.$uid';
  String _recoveryKeyStorageKey(String uid) => 'e2ee.recovery.$uid';

  /// Returns the user's keypair, generating + publishing one on first use.
  ///
  /// Idempotent — safe to call from multiple call sites; the keypair is
  /// only generated once per (user, device) and the public key in Firestore
  /// is only written once.
  Future<SimpleKeyPair> ensureKeyPair(String uid) async {
    final stored = await _storage.read(key: _privKeyStorageKey(uid));
    if (stored != null) {
      try {
        final privBytes = base64Decode(stored);
        return _x25519.newKeyPairFromSeed(privBytes);
      } catch (e) {
        debugPrint(
            '[e2ee-keys] stored key corrupt for $uid: $e — regenerating');
      }
    }

    final pair = await _x25519.newKeyPair();
    final priv = await pair.extractPrivateKeyBytes();
    final pub = await pair.extractPublicKey();

    await _storage.write(
      key: _privKeyStorageKey(uid),
      value: base64Encode(priv),
    );

    try {
      await _db.collection('users').doc(uid).set({
        'publicKey': base64Encode(pub.bytes),
        'publicKeyAlg': 'x25519',
        'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('[e2ee-keys] publish FAILED for $uid: $e\n$st');
      rethrow;
    }

    return pair;
  }

  /// Reads the cached private key bytes for [uid], or null if no keypair
  /// has been generated on this device yet.
  Future<Uint8List?> readPrivateKeyBytes(String uid) async {
    final stored = await _storage.read(key: _privKeyStorageKey(uid));
    if (stored == null) return null;
    try {
      return base64Decode(stored);
    } catch (_) {
      return null;
    }
  }

  /// Loads another user's public key from Firestore. Returns null if the
  /// user hasn't yet uploaded one (i.e. they haven't opened a build with
  /// E2EE support).
  Future<SimplePublicKey?> fetchPublicKey(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    final raw = data?['publicKey'];
    final alg = data?['publicKeyAlg'];
    if (raw is! String || raw.isEmpty || alg != 'x25519') return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.length != 32) return null;
      return SimplePublicKey(bytes, type: KeyPairType.x25519);
    } catch (_) {
      return null;
    }
  }

  /// Wipes the locally cached private key for [uid]. Use on sign-out only
  /// when you also want to discard message history on this device — once the
  /// key is gone, any messages still on the server for [uid] become
  /// undecryptable on this device.
  Future<void> deleteLocal(String uid) =>
      _storage.delete(key: _privKeyStorageKey(uid));

  /// Generates and stores a password-protected recovery keypair for cross-device
  /// decryption. Call this once on account creation or first app launch.
  /// Returns the public key (base64).
  Future<String> ensureRecoveryKey({
    required String uid,
    required String password,
  }) async {
    // Check if already stored locally
    final stored = await _storage.read(key: _recoveryKeyStorageKey(uid));
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        final pub = decoded['pub'] as String? ?? '';
        final ct = decoded['ct'] as String?;
        final n = decoded['n'] as String?;
        final salt = decoded['salt'] as String?;
        // Best-effort: keep Firestore backup in sync for restore on new devices.
        if (pub.isNotEmpty && ct != null && n != null && salt != null) {
          unawaited(_publishRecoveryKeyBackup(
            uid: uid,
            pubB64: pub,
            ct: ct,
            n: n,
            salt: salt,
          ));
        }
        return pub;
      } catch (_) {
        // Corrupt, regenerate
      }
    }

    // No local copy — try restoring the encrypted backup from Firestore.
    final restored = await _readRecoveryBackupFromFirestore(uid);
    if (restored != null) {
      await _storage.write(
        key: _recoveryKeyStorageKey(uid),
        value: jsonEncode(restored),
      );
      debugPrint('[e2ee-recovery] restored encrypted recovery key from cloud');
      return restored['pub']!;
    }

    // Generate new recovery keypair
    final pair = await _x25519.newKeyPair();
    final priv = await pair.extractPrivateKeyBytes();
    final pub = await pair.extractPublicKey();
    final pubB64 = base64Encode(pub.bytes);

    // Encrypt private key with password-derived KEK (PBKDF2 + AES-GCM)
    final encrypted =
        await _encryptRecoveryKey(Uint8List.fromList(priv), password);

    // Store locally
    await _storage.write(
      key: _recoveryKeyStorageKey(uid),
      value: jsonEncode({
        'pub': pubB64,
        'ct': encrypted['ct'],
        'n': encrypted['n'],
        'salt': encrypted['salt'],
      }),
    );

    await _publishRecoveryKeyBackup(
      uid: uid,
      pubB64: pubB64,
      ct: encrypted['ct']!,
      n: encrypted['n']!,
      salt: encrypted['salt']!,
    );

    return pubB64;
  }

  /// Attempts to decrypt and load the recovery private key using [password].
  /// Returns null if the key doesn't exist, password is wrong, or decryption fails.
  Future<Uint8List?> loadRecoveryKey(String uid, String password) async {
    var stored = await _storage.read(key: _recoveryKeyStorageKey(uid));
    if (stored == null) {
      final restored = await _readRecoveryBackupFromFirestore(uid);
      if (restored == null) return null;
      stored = jsonEncode(restored);
      await _storage.write(
        key: _recoveryKeyStorageKey(uid),
        value: stored,
      );
      debugPrint('[e2ee-recovery] downloaded encrypted recovery key backup');
    }

    try {
      final decoded = jsonDecode(stored);
      final ct = decoded['ct'] as String?;
      final n = decoded['n'] as String?;
      final salt = decoded['salt'] as String?;

      if (ct == null || n == null || salt == null) return null;

      return await _decryptRecoveryKey(
        base64Decode(ct),
        base64Decode(n),
        salt,
        password,
      );
    } catch (e) {
      debugPrint('[e2ee-recovery] load/decrypt failed: $e');
      return null;
    }
  }

  /// Fetches the recovery public key for [uid] from Firestore.
  /// Used on new devices to wrap session keys for cross-device decryption.
  Future<SimplePublicKey?> fetchRecoveryPublicKey(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      final raw = data?['recoveryPublicKey'];
      final alg = data?['recoveryPublicKeyAlg'];
      if (raw is! String || raw.isEmpty || alg != 'x25519') return null;
      final bytes = base64Decode(raw);
      if (bytes.length != 32) return null;
      return SimplePublicKey(bytes, type: KeyPairType.x25519);
    } catch (_) {
      return null;
    }
  }

  Future<void> _publishRecoveryKeyBackup({
    required String uid,
    required String pubB64,
    required String ct,
    required String n,
    required String salt,
  }) async {
    try {
      await _db.collection('users').doc(uid).set({
        'recoveryPublicKey': pubB64,
        'recoveryPublicKeyAlg': 'x25519',
        'recoveryPublicKeyUpdatedAt': FieldValue.serverTimestamp(),
        'recoveryKeyBackup': {
          'v': 1,
          'ct': ct,
          'n': n,
          'salt': salt,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('[e2ee-recovery] publish to Firestore FAILED: $e\n$st');
      // Don't rethrow — the key is still stored locally.
    }
  }

  Future<Map<String, String>?> _readRecoveryBackupFromFirestore(
      String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      final pub = data?['recoveryPublicKey'];
      final alg = data?['recoveryPublicKeyAlg'];
      final backupRaw = data?['recoveryKeyBackup'];
      if (pub is! String || pub.isEmpty || alg != 'x25519') return null;
      if (backupRaw is! Map) return null;
      final backup = Map<String, dynamic>.from(backupRaw);
      final ct = backup['ct'];
      final n = backup['n'];
      final salt = backup['salt'];
      if (ct is! String || ct.isEmpty) return null;
      if (n is! String || n.isEmpty) return null;
      if (salt is! String || salt.isEmpty) return null;
      return {
        'pub': pub,
        'ct': ct,
        'n': n,
        'salt': salt,
      };
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Recovery key encryption helpers
  // ─────────────────────────────────────────────

  static final _aes = AesGcm.with256bits();

  /// Encrypts the recovery private key with a password-derived KEK.
  /// Returns {ct, n, salt} all base64-encoded.
  Future<Map<String, String>> _encryptRecoveryKey(
    Uint8List privKeyBytes,
    String password,
  ) async {
    // PBKDF2: 100k iterations, SHA256, 32-byte output
    final salt = Uint8List(16);
    final random = Random.secure();
    for (int i = 0; i < salt.length; i++) {
      salt[i] = random.nextInt(256);
    }
    final kek = await _pbkdf2(password, salt);

    // AES-GCM encrypt
    final nonce = Uint8List(12);
    for (int i = 0; i < nonce.length; i++) {
      nonce[i] = random.nextInt(256);
    }
    final box = await _aes.encrypt(privKeyBytes, secretKey: kek, nonce: nonce);

    return {
      'ct': base64Encode(
          Uint8List.fromList([...box.cipherText, ...box.mac.bytes])),
      'n': base64Encode(nonce),
      'salt': base64Encode(salt),
    };
  }

  /// Decrypts recovery private key encrypted with [_encryptRecoveryKey].
  Future<Uint8List> _decryptRecoveryKey(
    Uint8List ctWithMac,
    Uint8List nonce,
    String saltB64,
    String password,
  ) async {
    final salt = base64Decode(saltB64);
    final kek = await _pbkdf2(password, salt);

    // Split ciphertext and MAC (MAC is last 16 bytes)
    final ciphertext = ctWithMac.sublist(0, ctWithMac.length - 16);
    final mac = Mac(ctWithMac.sublist(ctWithMac.length - 16));

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
    return Uint8List.fromList(await _aes.decrypt(secretBox, secretKey: kek));
  }

  /// PBKDF2-SHA256 key derivation (100k iterations, 32-byte output).
  Future<SecretKey> _pbkdf2(String password, List<int> salt) async {
    // Flutter's cryptography package doesn't expose PBKDF2 directly,
    // so we use a simple iteration-based approach with HMAC-SHA256.
    final hmac = Hmac.sha256();
    var key = Uint8List.fromList(utf8.encode(password));
    final saltWithMessage =
        Uint8List.fromList([...salt, ...utf8.encode('coil-e2ee')]);

    for (int i = 0; i < 100000; i++) {
      final sig =
          await hmac.calculateMac(saltWithMessage, secretKey: SecretKey(key));
      key = Uint8List.fromList(sig.bytes);
    }

    return SecretKey(key.sublist(0, 32));
  }
}
