import 'dart:convert';

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
        debugPrint('[e2ee-keys] stored key corrupt for $uid: $e — regenerating');
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
}
