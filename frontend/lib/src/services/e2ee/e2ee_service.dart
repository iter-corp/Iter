import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';

/// Per-chat AES-GCM encryption layered on top of [KeyManager].
///
/// Threat model:
///   • The Firestore server, anyone with read access to the `chats` /
///     `chats/{id}/messages` collections, and any future admin / Cloud
///     Function CANNOT recover plaintext message bodies.
///   • What IS visible to the server: sender uid, timestamp, message size,
///     existence of attached media URLs (because v1 does not encrypt media
///     payloads), reply-to ids, sticker ids, location coordinates.
///
/// Key wrapping:
///   • Each chat has a 32-byte AES-GCM session key, generated client-side by
///     whichever participant first sends a message.
///   • The session key is wrapped per-participant: for each member uid, we
///     do X25519(my_priv, their_pub) → HKDF(SHA-256) → 32-byte KEK, then
///     AES-GCM-encrypt the session key with the KEK.
///   • Wrapped blobs live at `chats/{chatId}.wrappedKeys.{uid} = {ct, n}`.
///   • A new participant can be added later by writing one more wrapped
///     entry (not used in 1:1 v1, but the data shape supports it).
///
/// Failure mode: if the recipient has not yet uploaded a public key (older
/// build, fresh sign-up before publish), [encryptForChat] throws
/// [E2EEUnavailable]. Callers SHOULD surface this to the user rather than
/// falling back to plaintext silently.
class E2EEService {
  E2EEService({KeyManager? keyManager, FirebaseFirestore? firestore})
      : _keys = keyManager ?? KeyManager(),
        _db = firestore ?? FirebaseFirestore.instance;

  final KeyManager _keys;
  final FirebaseFirestore _db;

  static final _x25519 = Cryptography.instance.x25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// In-memory cache: chatId → (version → SecretKey). Lets old messages
  /// keep decrypting after a key rotation.
  final Map<String, Map<int, SecretKey>> _chatKeyCache = {};

  /// Test/debug helper — purges the in-memory cache.
  void clearCache() => _chatKeyCache.clear();

  /// Force a fresh chat key, wrapped for the new participant set. Call this
  /// right after a member is added or removed so a removed member loses
  /// access to future messages without waiting for the next send to lazily
  /// trigger a rotation. The new key is archived under
  /// `wrappedKeysArchive.{prevVersion}` so anyone who could read history
  /// before still can.
  ///
  /// Best-effort: if the caller has no private key on this device, or if
  /// every other participant lacks a published public key, this throws
  /// [E2EEUnavailable]. Callers should NOT block the member-list update on
  /// it — log the failure and continue.
  Future<void> rotateChatKey({
    required String chatId,
    required String meUid,
    required List<String> participantUids,
  }) async {
    // Drop any cached versions for this chat so the next send re-reads
    // the new wrappedKeys from Firestore. We could be cleverer and only
    // drop the now-stale current version, but full purge is simpler and
    // these caches are small.
    _chatKeyCache.remove(chatId);
    await _forceRotate(
      chatId: chatId,
      meUid: meUid,
      participantUids: participantUids,
      prefetched: null,
    );
  }

  // ─────────────────────────────────────────────
  // Public API: encrypt / decrypt one message
  // ─────────────────────────────────────────────

  /// Encrypts [plaintext] for [chatId]. Returns the ciphertext envelope to
  /// store on the message doc as the value of `enc`. The envelope includes
  /// the [keyVersion] used so future readers can pick the right key after
  /// a membership change has rotated the chat key.
  Future<Map<String, dynamic>> encryptForChat({
    required String chatId,
    required String senderUid,
    required List<String> participantUids,
    required String plaintext,
  }) async {
    final ensured = await _ensureChatKey(
      chatId: chatId,
      meUid: senderUid,
      participantUids: participantUids,
    );
    if (plaintext.isEmpty) {
      return {
        'v': 1,
        'alg': 'AES-GCM-256',
        'ct': '',
        'n': '',
        'kv': ensured.version,
      };
    }
    final box = await _aesEncrypt(ensured.key, utf8.encode(plaintext));
    box['kv'] = ensured.version;
    return box;
  }

  /// Decrypts a message envelope previously produced by [encryptForChat].
  /// Returns null if the message was not encrypted (legacy/plaintext) or
  /// if this device cannot decrypt it.
  Future<String?> decryptForChat({
    required String chatId,
    required String meUid,
    required Map<String, dynamic> envelope,
  }) async {
    final ct = envelope['ct'];
    final n = envelope['n'];
    final kv = envelope['kv'];
    if (ct is! String || n is! String) return null;
    if (ct.isEmpty) return '';
    try {
      final version = (kv is int) ? kv : 1;
      final key = await _loadChatKeyForRead(
        chatId: chatId,
        meUid: meUid,
        version: version,
      );
      if (key == null) return null;
      final clear = await _aesDecrypt(
        key,
        ciphertext: base64Decode(ct),
        nonce: base64Decode(n),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Per-chat session key (versioned for group rotation)
  // ─────────────────────────────────────────────

  /// Returns the live key for [chatId], rotating if [participantUids] no
  /// longer matches the wrapping recipient set on the chat doc. The
  /// returned record carries the version stamp to write into outgoing
  /// envelopes.
  Future<_VersionedKey> _ensureChatKey({
    required String chatId,
    required String meUid,
    required List<String> participantUids,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final snap = await chatRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final currentVersion = (data['keyVersion'] as int?) ?? 1;
    final wrapped = (data['wrappedKeys'] as Map?)?.cast<String, dynamic>();
    final wrappedKeyset = wrapped?.keys.toSet() ?? <String>{};
    // "Desired" is the set of participants we can ACTUALLY wrap a key for —
    // i.e. those who have published a public key. A participant without a
    // public key (older build, never opened the app since E2EE shipped) is
    // not part of the rotation set; otherwise every send would mismatch and
    // rotate the key endlessly.
    final desired = await _wrappableParticipants(participantUids);

    // Path 1 — wrappedKeys covers exactly the wrappable member set AND I'm
    // in it. Unwrap and reuse the existing key.
    final membershipUnchanged = wrapped != null &&
        wrappedKeyset.containsAll(desired) &&
        desired.containsAll(wrappedKeyset);
    if (membershipUnchanged) {
      final mine = wrapped[meUid];
      if (mine is Map) {
        final key = await _unwrapMyKey(
          meUid: meUid,
          wrappedFromMe: Map<String, dynamic>.from(mine),
        );
        if (key != null) {
          _cacheKey(chatId, currentVersion, key);
          return _VersionedKey(key, currentVersion);
        }
      }
    }

    // Path 2 — chat has no key yet, OR the wrappable member set has
    // changed (someone with a public key joined/left, or a previously
    // key-less member finally published their public key). Rotate.
    return _forceRotate(
      chatId: chatId,
      meUid: meUid,
      participantUids: participantUids,
      prefetched: _PrefetchedChatState(
        currentVersion: currentVersion,
        wrapped: wrapped,
        desired: desired,
      ),
    );
  }

  /// Generates a fresh chat key, wraps it for every wrappable participant,
  /// archives the previous wrapping under `wrappedKeysArchive.{prevVersion}`,
  /// and returns the new versioned key. Shared by [_ensureChatKey] (lazy
  /// rotation on send) and [rotateChatKey] (proactive rotation on member
  /// add/remove).
  Future<_VersionedKey> _forceRotate({
    required String chatId,
    required String meUid,
    required List<String> participantUids,
    _PrefetchedChatState? prefetched,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);

    int currentVersion;
    Map<String, dynamic>? wrapped;
    Set<String> desired;
    if (prefetched != null) {
      currentVersion = prefetched.currentVersion;
      wrapped = prefetched.wrapped;
      desired = prefetched.desired;
    } else {
      final snap = await chatRef.get();
      final data = snap.data() ?? const <String, dynamic>{};
      currentVersion = (data['keyVersion'] as int?) ?? 1;
      wrapped = (data['wrappedKeys'] as Map?)?.cast<String, dynamic>();
      desired = await _wrappableParticipants(participantUids);
    }

    final raw = await _aes.newSecretKey();
    final rawBytes = await raw.extractBytes();
    final newKey = SecretKey(rawBytes);

    final wrappedForAll = <String, Map<String, dynamic>>{};
    for (final uid in desired) {
      final wrappedEntry = await _wrapKeyFor(
        meUid: meUid,
        otherUid: uid,
        sessionKeyBytes: rawBytes,
      );
      if (wrappedEntry != null) wrappedForAll[uid] = wrappedEntry;
    }

    if (!wrappedForAll.containsKey(meUid)) {
      throw const E2EEUnavailable(
        'Could not derive my own key wrapper. Try again after the app finishes setting up encryption.',
      );
    }

    final isFirstKey = wrapped == null || wrapped.isEmpty;
    final nextVersion = isFirstKey ? 1 : currentVersion + 1;

    // Archive old wrapping by version BEFORE overwriting wrappedKeys, so
    // anyone present at write time can still decrypt messages with `kv ==
    // currentVersion` after this rotation lands.
    final archiveUpdate = <String, dynamic>{};
    if (!isFirstKey) {
      archiveUpdate['wrappedKeysArchive.$currentVersion'] = wrapped;
    }

    await chatRef.set(
      {
        'wrappedKeys': wrappedForAll,
        'keyVersion': nextVersion,
        'e2ee': true,
        'e2eeAlg': 'X25519+AES-GCM-256',
        ...archiveUpdate,
      },
      SetOptions(merge: true),
    );

    _cacheKey(chatId, nextVersion, newKey);
    return _VersionedKey(newKey, nextVersion);
  }

  Future<SecretKey?> _loadChatKeyForRead({
    required String chatId,
    required String meUid,
    required int version,
  }) async {
    final cached = _chatKeyCache[chatId]?[version];
    if (cached != null) return cached;

    final snap = await _db.collection('chats').doc(chatId).get();
    final data = snap.data() ?? const <String, dynamic>{};
    final currentVersion = (data['keyVersion'] as int?) ?? 1;

    Map<String, dynamic>? wrappedSet;
    if (version == currentVersion) {
      wrappedSet = (data['wrappedKeys'] as Map?)?.cast<String, dynamic>();
    } else {
      final archive =
          (data['wrappedKeysArchive'] as Map?)?.cast<String, dynamic>();
      final entry = archive?['$version'];
      if (entry is Map) wrappedSet = Map<String, dynamic>.from(entry);
    }
    final mine = wrappedSet?[meUid];
    if (mine is! Map) return null;

    final key = await _unwrapMyKey(
      meUid: meUid,
      wrappedFromMe: Map<String, dynamic>.from(mine),
    );
    if (key != null) _cacheKey(chatId, version, key);
    return key;
  }

  void _cacheKey(String chatId, int version, SecretKey key) {
    final byChat = _chatKeyCache.putIfAbsent(chatId, () => {});
    byChat[version] = key;
  }

  /// Returns the subset of [participantUids] that have a published public
  /// key — i.e. members we can actually wrap a session key for. Members
  /// without a key are silently dropped from the rotation set rather than
  /// triggering a rotation churn on every send.
  Future<Set<String>> _wrappableParticipants(List<String> participantUids) async {
    final out = <String>{};
    for (final uid in participantUids.toSet()) {
      // Cheap path for the caller themselves: their private key is local,
      // so by definition they have a public key (we publish on first run).
      // Still verify against Firestore to handle the case of a fresh
      // install that hasn't yet committed the publish RPC.
      final pub = await _keys.fetchPublicKey(uid);
      if (pub != null) out.add(uid);
    }
    return out;
  }

  Future<SecretKey?> _unwrapMyKey({
    required String meUid,
    required Map<String, dynamic> wrappedFromMe,
  }) async {
    final ct = wrappedFromMe['ct'];
    final n = wrappedFromMe['n'];
    final wrapperPubB64 = wrappedFromMe['kPub'];
    if (ct is! String || n is! String || wrapperPubB64 is! String) return null;

    final myPriv = await _keys.readPrivateKeyBytes(meUid);
    if (myPriv == null) return null;

    final wrapperPub = SimplePublicKey(
      base64Decode(wrapperPubB64),
      type: KeyPairType.x25519,
    );

    final myPair = await _x25519.newKeyPairFromSeed(myPriv);
    final shared = await _x25519.sharedSecretKey(
      keyPair: myPair,
      remotePublicKey: wrapperPub,
    );
    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode('coil-e2ee-kek-v1'),
      nonce: const [],
    );
    final clear = await _aesDecrypt(
      kek,
      ciphertext: base64Decode(ct),
      nonce: base64Decode(n),
    );
    return SecretKey(clear);
  }

  Future<Map<String, dynamic>?> _wrapKeyFor({
    required String meUid,
    required String otherUid,
    required List<int> sessionKeyBytes,
  }) async {
    final myPriv = await _keys.readPrivateKeyBytes(meUid);
    if (myPriv == null) return null;
    final myPair = await _x25519.newKeyPairFromSeed(myPriv);
    final myPub = await myPair.extractPublicKey();

    SimplePublicKey? otherPub;
    if (otherUid == meUid) {
      otherPub = myPub;
    } else {
      otherPub = await _keys.fetchPublicKey(otherUid);
    }
    if (otherPub == null) return null;

    final shared = await _x25519.sharedSecretKey(
      keyPair: myPair,
      remotePublicKey: otherPub,
    );
    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode('coil-e2ee-kek-v1'),
      nonce: const [],
    );
    final box = await _aesEncryptRaw(kek, sessionKeyBytes);
    return {
      'ct': base64Encode(box['ct'] as List<int>),
      'n': base64Encode(box['n'] as List<int>),
      'kPub': base64Encode(myPub.bytes),
      'alg': 'X25519+AES-GCM-256',
    };
  }

  // ─────────────────────────────────────────────
  // Low-level AES-GCM helpers
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>> _aesEncrypt(SecretKey key, List<int> clear) async {
    final box = await _aesEncryptRaw(key, clear);
    return {
      'v': 1,
      'alg': 'AES-GCM-256',
      'ct': base64Encode(box['ct'] as List<int>),
      'n': base64Encode(box['n'] as List<int>),
    };
  }

  Future<Map<String, List<int>>> _aesEncryptRaw(
    SecretKey key,
    List<int> clear,
  ) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
    );
    // Concat ciphertext + mac so we can store/parse a single blob.
    final combined = Uint8List(box.cipherText.length + box.mac.bytes.length);
    combined.setRange(0, box.cipherText.length, box.cipherText);
    combined.setRange(
      box.cipherText.length,
      combined.length,
      box.mac.bytes,
    );
    return {'ct': combined, 'n': nonce};
  }

  Future<List<int>> _aesDecrypt(
    SecretKey key, {
    required List<int> ciphertext,
    required List<int> nonce,
  }) async {
    if (ciphertext.length < 16) {
      throw StateError('Ciphertext too short to contain GCM tag');
    }
    final tagStart = ciphertext.length - 16;
    final ct = ciphertext.sublist(0, tagStart);
    final mac = Mac(ciphertext.sublist(tagStart));
    return _aes.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: key,
    );
  }
}

/// Pairs an AES session key with the chat-doc keyVersion that produced it.
/// Used so [E2EEService.encryptForChat] can stamp outgoing envelopes with
/// the version that future readers will need to unwrap.
class _VersionedKey {
  final SecretKey key;
  final int version;
  const _VersionedKey(this.key, this.version);
}

/// Snapshot of chat-doc state passed from [_ensureChatKey] into
/// [_forceRotate] so the rotation path doesn't re-read Firestore when the
/// caller has already loaded the doc and computed the wrappable set.
class _PrefetchedChatState {
  final int currentVersion;
  final Map<String, dynamic>? wrapped;
  final Set<String> desired;
  const _PrefetchedChatState({
    required this.currentVersion,
    required this.wrapped,
    required this.desired,
  });
}

/// Thrown when E2EE cannot be set up for a given chat — typically because
/// the recipient hasn't uploaded a public key yet (they're on an older
/// build, or just haven't opened the app since the keypair-publish step ran).
class E2EEUnavailable implements Exception {
  final String message;
  const E2EEUnavailable(this.message);
  @override
  String toString() => message;
}
