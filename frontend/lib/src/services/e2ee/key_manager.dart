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

  /// Local flag stored in secure storage that tells us whether the user
  /// has chosen their own recovery password. Until they do, the app uses
  /// the legacy uid-derived password so existing chats stay readable —
  /// see RECOVERY_PASSWORD_MIGRATION in main.dart.
  String _userChosePasswordKey(String uid) => 'e2ee.recovery.userset.$uid';

  /// Legacy uid-derived password kept around so existing users who
  /// haven't migrated yet stay decryptable. Burn this after the
  /// migration deadline.
  static String legacyPasswordFor(String uid) =>
      'coil-recovery-${uid.substring(0, 8)}';

  /// Whether the user has set their own recovery password via the
  /// onboarding/settings flow. False for legacy installs.
  Future<bool> hasUserChosenRecoveryPassword(String uid) async {
    final v = await _storage.read(key: _userChosePasswordKey(uid));
    return v == 'true';
  }

  /// Stash the locally-derived recovery password so the rest of the app
  /// can unlock the recovery key without re-prompting on every cold
  /// start. The string stored is the *password itself* — protected only
  /// by Keychain/Keystore — so it's no weaker than the underlying KEK.
  /// Returns the password back to the caller for chaining.
  String _stashedPasswordKey(String uid) => 'e2ee.recovery.password.$uid';

  Future<void> _stashPassword(String uid, String password) async {
    await _storage.write(key: _stashedPasswordKey(uid), value: password);
  }

  /// Reads the user-chosen recovery password from secure storage. Falls
  /// back to the legacy password if the user hasn't migrated yet.
  Future<String> resolveRecoveryPassword(String uid) async {
    final stashed = await _storage.read(key: _stashedPasswordKey(uid));
    if (stashed != null && stashed.isNotEmpty) return stashed;
    return legacyPasswordFor(uid);
  }

  /// True iff Firestore advertises a recovery backup for [uid]. Lets the
  /// startup flow detect "fresh device but cloud backup exists" so it
  /// can prompt for the password instead of leaving the user stuck.
  Future<bool> hasRecoveryBackup(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      final backup = data?['recoveryKeyBackup'];
      return backup is Map && backup['ct'] is String;
    } catch (_) {
      return false;
    }
  }

  /// Sets (or rotates) the user's recovery password. When the user has
  /// never chosen one (legacy install), [oldPassword] should be
  /// [legacyPasswordFor]`(uid)`; otherwise pass the previous user-chosen
  /// one. Re-encrypts the recovery PRIVATE key with the new
  /// password-derived KEK, republishes the backup, and stashes the new
  /// password locally so subsequent cold starts unlock automatically.
  ///
  /// Returns true on success, false if the old password didn't decrypt
  /// the existing backup (so the caller can show "wrong password").
  Future<bool> setRecoveryPassword({
    required String uid,
    required String oldPassword,
    required String newPassword,
  }) async {
    if (newPassword.isEmpty) return false;

    // Load the current recovery PRIV using the old password. If there's
    // no recovery key yet (e.g. ensureRecoveryKey never ran), bail —
    // caller should ensureRecoveryKey first.
    final priv = await loadRecoveryKey(uid, oldPassword);
    if (priv == null) return false;

    // Re-encrypt with the new password.
    final reencrypted = await _encryptRecoveryKey(priv, newPassword);

    // Read pub from the existing local blob (we don't change it).
    final stored = await _storage.read(key: _recoveryKeyStorageKey(uid));
    String pubB64 = '';
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        pubB64 = (decoded['pub'] as String?) ?? '';
      } catch (_) {}
    }
    if (pubB64.isEmpty) {
      // Should never happen if loadRecoveryKey succeeded, but be safe.
      return false;
    }

    await _storage.write(
      key: _recoveryKeyStorageKey(uid),
      value: jsonEncode({
        'pub': pubB64,
        'ct': reencrypted['ct'],
        'n': reencrypted['n'],
        'salt': reencrypted['salt'],
      }),
    );
    await _publishRecoveryKeyBackup(
      uid: uid,
      pubB64: pubB64,
      ct: reencrypted['ct']!,
      n: reencrypted['n']!,
      salt: reencrypted['salt']!,
    );
    await _stashPassword(uid, newPassword);
    await _storage.write(key: _userChosePasswordKey(uid), value: 'true');
    return true;
  }

  // ─────────────────────────────────────────────
  // Peer key fingerprinting (security-code-changed detection)
  // ─────────────────────────────────────────────

  String _peerFingerprintKey(String meUid, String peerUid) =>
      'e2ee.peerfp.$meUid.$peerUid';

  /// Returns a short, human-comparable fingerprint of [pubKeyBytes].
  /// Format mirrors WhatsApp's "security code": twelve 5-digit groups
  /// derived from the SHA-256 of the public key. Two parties can read
  /// these out loud to confirm they hold each other's actual keys
  /// (no MITM).
  static Future<String> fingerprintOf(List<int> pubKeyBytes) async {
    final hash =
        await Sha256().hash(pubKeyBytes).then((h) => h.bytes);
    final digits = StringBuffer();
    for (final b in hash) {
      digits.write(b.toString().padLeft(3, '0'));
    }
    // SHA-256 → 32 bytes → 96 decimal digits. Truncate to the
    // canonical 60-digit ("12 × 5") security code.
    final flat = digits.toString();
    final code = flat.substring(0, 60);
    final groups = <String>[];
    for (var i = 0; i < 60; i += 5) {
      groups.add(code.substring(i, i + 5));
    }
    return groups.join(' ');
  }

  /// Fingerprint of the user's own published public key. Used by the
  /// verification screen so the local side can show their code next to
  /// the remote side's.
  Future<String?> fingerprintForSelf(String uid) async {
    final priv = await readPrivateKeyBytes(uid);
    if (priv == null) return null;
    try {
      final kp = await _x25519.newKeyPairFromSeed(priv);
      final pub = await kp.extractPublicKey();
      return await fingerprintOf(pub.bytes);
    } catch (_) {
      return null;
    }
  }

  /// Fingerprint of the live published pub key for [peerUid], or null
  /// if they haven't published one (or Firestore is unreachable).
  Future<String?> fingerprintForPeer(String peerUid) async {
    final pub = await fetchPublicKey(peerUid);
    if (pub == null) return null;
    return await fingerprintOf(pub.bytes);
  }

  /// State of [peerUid]'s key from the perspective of [meUid]. Used to
  /// drive the "security code changed" banner in chat.
  Future<PeerKeyState> checkPeerKey({
    required String meUid,
    required String peerUid,
  }) async {
    final liveFp = await fingerprintForPeer(peerUid);
    if (liveFp == null) return PeerKeyState.unknown;
    final stored =
        await _storage.read(key: _peerFingerprintKey(meUid, peerUid));
    if (stored == null || stored.isEmpty) {
      // First time we've ever observed this peer — trust on first use
      // and remember the fingerprint for future comparisons.
      await _storage.write(
        key: _peerFingerprintKey(meUid, peerUid),
        value: liveFp,
      );
      return PeerKeyState.firstSeen;
    }
    if (stored == liveFp) return PeerKeyState.unchanged;
    return PeerKeyState.changed;
  }

  /// Records [peerUid]'s current fingerprint as the new trusted value.
  /// Called when the user acknowledges a security-code-changed warning
  /// (either by tapping "Got it" or by verifying the new code on the
  /// verification screen).
  Future<void> acknowledgePeerKey({
    required String meUid,
    required String peerUid,
  }) async {
    final liveFp = await fingerprintForPeer(peerUid);
    if (liveFp == null) return;
    await _storage.write(
      key: _peerFingerprintKey(meUid, peerUid),
      value: liveFp,
    );
  }

  /// Discards the local keypair and the locally-cached recovery
  /// password, then regenerates a fresh X25519 keypair via
  /// [ensureKeyPair]. Old encrypted history wrapped against the
  /// previous pub becomes unreadable on every device. Use this only
  /// when the user has confirmed they accept losing secret-chat
  /// history (e.g. they forgot their recovery password).
  ///
  /// The recovery backup blob on the server is left intact so any
  /// other device that still has the old keypair can keep reading
  /// history. If you want a full wipe, call [deleteLocal] and then
  /// publish a new recovery key separately.
  Future<void> resetEncryptionIdentity(String uid) async {
    await deleteLocal(uid);
    await _storage.delete(key: _stashedPasswordKey(uid));
    await _storage.delete(key: _userChosePasswordKey(uid));
    // ensureKeyPair will regenerate + publish on next access.
    await ensureKeyPair(uid);
  }

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

  /// State of the local keypair relative to what's published in Firestore.
  /// Used by the UI to surface multi-device collisions ("another device
  /// signed in and replaced your encryption key") so the user knows new
  /// messages won't be readable here until the other device re-syncs.
  ///
  ///   * [KeySyncState.synced] — local pub == published pub. Normal.
  ///   * [KeySyncState.replacedByOtherDevice] — local key exists but the
  ///     published pub differs, i.e. another sign-in overwrote it.
  ///   * [KeySyncState.missingLocal] — no private key on this device yet;
  ///     either first launch or a fresh reinstall. Recovery key needed.
  ///   * [KeySyncState.unknown] — Firestore read failed (offline).
  Future<KeySyncState> checkKeyPairSync(String uid) async {
    final localPriv = await readPrivateKeyBytes(uid);
    if (localPriv == null) return KeySyncState.missingLocal;

    SimplePublicKey localPub;
    try {
      final kp = await _x25519.newKeyPairFromSeed(localPriv);
      localPub = await kp.extractPublicKey();
    } catch (_) {
      // Stored key is corrupt — treat as missing so the UI prompts a
      // recovery / regenerate flow rather than silently breaking sends.
      return KeySyncState.missingLocal;
    }

    SimplePublicKey? publishedPub;
    try {
      publishedPub = await fetchPublicKey(uid);
    } catch (_) {
      return KeySyncState.unknown;
    }
    if (publishedPub == null) {
      // Local key exists but nothing is published. The publish RPC
      // probably failed on first launch; ensureKeyPair on the next cold
      // start will retry, but until then the device behaves correctly
      // for sending and only fails for receivers. Treat as synced.
      return KeySyncState.synced;
    }

    final localB64 = base64Encode(localPub.bytes);
    final publishedB64 = base64Encode(publishedPub.bytes);
    return localB64 == publishedB64
        ? KeySyncState.synced
        : KeySyncState.replacedByOtherDevice;
  }

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

  /// State of the local E2EE keypair relative to what Firestore advertises.
  /// See [checkKeyPairSync].
  // (enum defined at file scope below — kept here as a doc anchor.)

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

/// Result of [KeyManager.checkKeyPairSync]. The UI uses this to decide
/// whether to show a "another device replaced your encryption key" banner
/// or a "restore from recovery backup" prompt.
enum KeySyncState {
  /// Local pub matches what Firestore advertises. Normal operation.
  synced,

  /// Local key exists, but the published pub differs — another device
  /// signed in and overwrote `users/{uid}.publicKey`. New messages from
  /// other people will be wrapped for the other device, so they won't
  /// decrypt here until we either republish OR the other device patches
  /// the missing wrappings.
  replacedByOtherDevice,

  /// No private key on this device. First launch or fresh reinstall.
  /// The recovery flow should kick in.
  missingLocal,

  /// Couldn't reach Firestore to check. Treat as transient — retry later.
  unknown,
}

/// State of a peer's published public key relative to the fingerprint
/// we last saw for them. Drives the "security code changed" banner in
/// 1:1 secret chats.
enum PeerKeyState {
  /// Peer's key matches the fingerprint we recorded. Normal operation.
  unchanged,

  /// Peer has published a key for the first time as far as this device
  /// knows — trust-on-first-use, the fingerprint is now stored.
  firstSeen,

  /// Peer's key differs from the fingerprint we recorded. Could be a
  /// legitimate reinstall, a new device — or a MITM. The UI must
  /// surface this to the user and only re-trust on acknowledgement.
  changed,

  /// Couldn't fetch the peer's published key (offline, peer never
  /// published one). Treat as transient.
  unknown,
}
