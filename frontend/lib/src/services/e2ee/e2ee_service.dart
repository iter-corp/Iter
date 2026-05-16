import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

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

  /// Cache of decrypted recovery private keys: uid → privKeyBytes.
  /// Allows reuse of recovery key across multiple decryptions without
  /// re-prompting for password.
  final Map<String, Uint8List> _recoveryKeyCache = {};

  /// Test/debug helper — purges the in-memory cache.
  void clearCache() {
    _chatKeyCache.clear();
    _recoveryKeyCache.clear();
  }

  /// Unlocks the recovery key for [uid] using [password]. Once unlocked,
  /// it will be cached in memory and used for cross-device decryption.
  /// Returns true if successful, false if the key doesn't exist or password is wrong.
  Future<bool> unlockRecoveryKey(String uid, String password) async {
    try {
      final privKey = await _keys.loadRecoveryKey(uid, password);
      if (privKey != null) {
        _recoveryKeyCache[uid] = privKey;
        debugPrint('[e2ee] recovery key unlocked for $uid');
        return true;
      }
    } catch (e) {
      debugPrint('[e2ee] unlock recovery key failed: $e');
    }
    return false;
  }

  /// Returns true if the recovery key for [uid] is currently cached in memory.
  bool isRecoveryKeyUnlocked(String uid) => _recoveryKeyCache.containsKey(uid);

  /// Scans all key versions (current + archive) for [chatId] and adds
  /// wrapping entries for any [participantUids] that are missing one — as
  /// long as [meUid] is already wrapped in those versions (so they can
  /// decrypt the session key and re-wrap it for the missing participant).
  ///
  /// Call this once when opening a chat (e.g. from [streamMessages]) so
  /// that messages sent before another participant published their public
  /// key become readable for them on the next stream event.
  Future<void> patchMissingWrappings({
    required String chatId,
    required String meUid,
    required List<String> participantUids,
  }) async {
    try {
      final chatRef = _db.collection('chats').doc(chatId);
      final snap = await chatRef.get();
      final data = snap.data();
      if (data == null) return;

      final desired = await _wrappableParticipants(participantUids);
      final updates = <String, dynamic>{};

      // Compute my current public key once — used to detect old-format entries
      // where I was the sender (kPub == mine) so we can re-wrap and stamp rPub.
      String? myCurrentPubB64;
      try {
        final priv = await _keys.readPrivateKeyBytes(meUid);
        if (priv != null) {
          final kp = await _x25519.newKeyPairFromSeed(priv);
          final pub = await kp.extractPublicKey();
          myCurrentPubB64 = base64Encode(pub.bytes);
        }
      } catch (_) {}

      // Check current wrappedKeys
      final currentWrapped =
          (data['wrappedKeys'] as Map?)?.cast<String, dynamic>();
      if (currentWrapped != null) {
        // Build set of UIDs that are either missing or have a stale rPub
        // (stale = the stored recipient public key no longer matches what's
        //  published in Firestore, meaning the recipient reinstalled / rotated keys).
        final needsWrap = <String>{};
        for (final uid in desired) {
          if (!currentWrapped.containsKey(uid)) {
            needsWrap.add(uid);
          } else {
            // Check if rPub is stale
            final existingEntry = currentWrapped[uid];
            if (existingEntry is Map) {
              final storedRPub = existingEntry['rPub'] as String?;
              if (storedRPub != null) {
                try {
                  final currentPub = uid == meUid
                      ? await (() async {
                          final priv = await _keys.readPrivateKeyBytes(uid);
                          if (priv == null) return null;
                          final kp = await _x25519.newKeyPairFromSeed(priv);
                          return kp.extractPublicKey();
                        })()
                      : await _keys.fetchPublicKey(uid);
                  if (currentPub != null) {
                    final currentPubB64 = base64Encode(currentPub.bytes);
                    if (currentPubB64 != storedRPub) {
                      needsWrap.add(uid);
                    }
                  }
                } catch (_) {}
              } else {
                // Old format: no rPub stored. If I was the sender (kPub matches
                // my current public key), re-wrap so the entry gets rPub stamped
                // and picks up the recipient's current public key.
                final storedKPub = existingEntry['kPub'] as String?;
                if (storedKPub != null &&
                    myCurrentPubB64 != null &&
                    storedKPub == myCurrentPubB64) {
                  needsWrap.add(uid);
                }
              }
            }
          }
        }
        if (needsWrap.isNotEmpty) {
          final mineMine = currentWrapped[meUid];
          if (mineMine is Map) {
            final sessionKey = await _unwrapMyKey(
              meUid: meUid,
              wrappedFromMe: Map<String, dynamic>.from(mineMine),
            );
            if (sessionKey != null) {
              final sessionKeyBytes = await sessionKey.extractBytes();
              final patchedWrapped = Map<String, dynamic>.from(currentWrapped);
              for (final uid in needsWrap) {
                final entry = await _wrapKeyFor(
                  meUid: meUid,
                  otherUid: uid,
                  sessionKeyBytes: sessionKeyBytes,
                );
                if (entry != null) {
                  patchedWrapped[uid] = entry;
                  try {
                    final recoveryPub = await _keys.fetchRecoveryPublicKey(uid);
                    if (recoveryPub != null) {
                      final recoveryEntry = await _wrapKeyForRecovery(
                        meUid: meUid,
                        participantUid: uid,
                        recoveryPublicKey: recoveryPub,
                        sessionKeyBytes: sessionKeyBytes,
                      );
                      if (recoveryEntry != null) {
                        patchedWrapped[uid] = {
                          ...entry,
                          'recoveryWrapped': recoveryEntry
                        };
                      }
                    }
                  } catch (_) {}
                }
              }
              updates['wrappedKeys'] = patchedWrapped;
            }
          }
        }
      }

      // Check archived versions
      final archive =
          (data['wrappedKeysArchive'] as Map?)?.cast<String, dynamic>();
      if (archive != null) {
        for (final versionStr in archive.keys) {
          final archiveEntry = archive[versionStr];
          if (archiveEntry is! Map) continue;
          final archiveWrapped = Map<String, dynamic>.from(archiveEntry);

          // Also catch stale rPub in archive entries
          final needsWrapArchive = <String>{};
          for (final uid in desired) {
            if (!archiveWrapped.containsKey(uid)) {
              needsWrapArchive.add(uid);
            } else {
              final existingEntry = archiveWrapped[uid];
              if (existingEntry is Map) {
                final storedRPub = existingEntry['rPub'] as String?;
                if (storedRPub != null) {
                  try {
                    final currentPub = uid == meUid
                        ? await (() async {
                            final priv = await _keys.readPrivateKeyBytes(uid);
                            if (priv == null) return null;
                            final kp = await _x25519.newKeyPairFromSeed(priv);
                            return kp.extractPublicKey();
                          })()
                        : await _keys.fetchPublicKey(uid);
                    if (currentPub != null &&
                        base64Encode(currentPub.bytes) != storedRPub) {
                      needsWrapArchive.add(uid);
                    }
                  } catch (_) {}
                } else {
                  // Old format: no rPub. Re-wrap if I was the sender.
                  final storedKPub = existingEntry['kPub'] as String?;
                  if (storedKPub != null &&
                      myCurrentPubB64 != null &&
                      storedKPub == myCurrentPubB64) {
                    needsWrapArchive.add(uid);
                  }
                }
              }
            }
          }
          if (needsWrapArchive.isEmpty) continue;

          final archiveMine = archiveWrapped[meUid];
          if (archiveMine is! Map) continue;

          final archiveKey = await _unwrapMyKey(
            meUid: meUid,
            wrappedFromMe: Map<String, dynamic>.from(archiveMine),
          );
          if (archiveKey == null) continue;

          final archiveKeyBytes = await archiveKey.extractBytes();
          bool changed = false;
          for (final uid in needsWrapArchive) {
            final entry = await _wrapKeyFor(
              meUid: meUid,
              otherUid: uid,
              sessionKeyBytes: archiveKeyBytes,
            );
            if (entry != null) {
              archiveWrapped[uid] = entry;
              changed = true;
            }
          }
          if (changed) {
            updates['wrappedKeysArchive.$versionStr'] = archiveWrapped;
          }
        }
      }

      if (updates.isNotEmpty) {
        await chatRef.update(updates);
        // Clear cache so the next read picks up the new wrappings from Firestore.
        _chatKeyCache.remove(chatId);
      }
    } catch (_) {}
  }

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
    Map<String, dynamic>? archiveData; // for backfilling older versions
    if (prefetched != null) {
      currentVersion = prefetched.currentVersion;
      wrapped = prefetched.wrapped;
      desired = prefetched.desired;
      // Fetch archive data separately for backfill if there are older versions
      if (currentVersion > 1) {
        try {
          final snap = await chatRef.get();
          final d = snap.data() ?? const <String, dynamic>{};
          archiveData =
              (d['wrappedKeysArchive'] as Map?)?.cast<String, dynamic>();
        } catch (_) {}
      }
    } else {
      final snap = await chatRef.get();
      final data = snap.data() ?? const <String, dynamic>{};
      currentVersion = (data['keyVersion'] as int?) ?? 1;
      wrapped = (data['wrappedKeys'] as Map?)?.cast<String, dynamic>();
      desired = await _wrappableParticipants(participantUids);
      archiveData =
          (data['wrappedKeysArchive'] as Map?)?.cast<String, dynamic>();
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
      if (wrappedEntry != null) {
        wrappedForAll[uid] = wrappedEntry;
      }
    }

    // Also wrap for each participant's recovery key for cross-device access.
    for (final uid in desired) {
      try {
        final recoveryPub = await _keys.fetchRecoveryPublicKey(uid);
        if (recoveryPub != null) {
          final recoveryWrapped = await _wrapKeyForRecovery(
            meUid: meUid,
            participantUid: uid,
            recoveryPublicKey: recoveryPub,
            sessionKeyBytes: rawBytes,
          );
          if (recoveryWrapped != null) {
            final existing = wrappedForAll[uid] ?? <String, dynamic>{};
            existing['recoveryWrapped'] = recoveryWrapped;
            wrappedForAll[uid] = existing;
          }
        }
      } catch (e) {
        debugPrint('[e2ee-rotate] recovery wrapping failed for $uid: $e');
        // Continue without recovery key for this participant
      }
    }

    if (!wrappedForAll.containsKey(meUid)) {
      throw const E2EEUnavailable(
        'Could not derive my own key wrapper. Try again after the app finishes setting up encryption.',
      );
    }

    final isFirstKey = wrapped == null || wrapped.isEmpty;
    final nextVersion = isFirstKey ? 1 : currentVersion + 1;

    // Backfill: if new participants joined (were not in old wrapped), re-wrap
    // the current session key for them before archiving. This lets newly added
    // members decrypt messages that were encrypted with the old key version.
    Map<String, dynamic>? wrappedToArchive = wrapped;
    if (!isFirstKey) {
      final wrappedKeyset = wrapped.keys.toSet();
      final newParticipants = desired.difference(wrappedKeyset);
      if (newParticipants.isNotEmpty) {
        final mineCurrent = wrapped[meUid];
        if (mineCurrent is Map) {
          final currentKey = await _unwrapMyKey(
            meUid: meUid,
            wrappedFromMe: Map<String, dynamic>.from(mineCurrent),
          );
          if (currentKey != null) {
            final currentKeyBytes = await currentKey.extractBytes();
            final backfilled = Map<String, dynamic>.from(wrapped);
            for (final newUid in newParticipants) {
              final entry = await _wrapKeyFor(
                meUid: meUid,
                otherUid: newUid,
                sessionKeyBytes: currentKeyBytes,
              );
              if (entry != null) {
                backfilled[newUid] = entry;
                // Also add recovery key wrapping for the new participant.
                try {
                  final recoveryPub =
                      await _keys.fetchRecoveryPublicKey(newUid);
                  if (recoveryPub != null) {
                    final recoveryEntry = await _wrapKeyForRecovery(
                      meUid: meUid,
                      participantUid: newUid,
                      recoveryPublicKey: recoveryPub,
                      sessionKeyBytes: currentKeyBytes,
                    );
                    if (recoveryEntry != null) {
                      backfilled[newUid] = {
                        ...entry,
                        'recoveryWrapped': recoveryEntry,
                      };
                    }
                  }
                } catch (_) {}
              }
            }
            wrappedToArchive = backfilled;
            debugPrint(
              '[e2ee-rotate] backfilled ${newParticipants.length} new participant(s) into v$currentVersion archive: $newParticipants',
            );
          }
        }
      }
    }

    // Archive old wrapping by version BEFORE overwriting wrappedKeys, so
    // anyone present at write time can still decrypt messages with `kv ==
    // currentVersion` after this rotation lands.
    final archiveUpdate = <String, dynamic>{};
    if (!isFirstKey) {
      archiveUpdate['wrappedKeysArchive.$currentVersion'] = wrappedToArchive;
    }

    // Backfill older archive versions for newly added participants.
    // This lets User B decrypt messages from before they had a public key.
    if (!isFirstKey && archiveData != null) {
      final wrappedKeyset = wrapped.keys.toSet();
      final newParticipants = desired.difference(wrappedKeyset);
      if (newParticipants.isNotEmpty) {
        for (final versionStr in archiveData.keys) {
          final archiveEntry = archiveData[versionStr];
          if (archiveEntry is! Map) continue;
          final archiveWrapped = Map<String, dynamic>.from(archiveEntry);

          // Skip if all new participants are already wrapped in this archive version
          if (newParticipants.every((uid) => archiveWrapped.containsKey(uid))) {
            continue;
          }

          // Need meUid's entry in this archive version to decrypt the session key
          final archiveMine = archiveWrapped[meUid];
          if (archiveMine is! Map) continue;

          final archiveKey = await _unwrapMyKey(
            meUid: meUid,
            wrappedFromMe: Map<String, dynamic>.from(archiveMine),
          );
          if (archiveKey == null) continue;

          final archiveKeyBytes = await archiveKey.extractBytes();
          bool changed = false;
          for (final newUid in newParticipants) {
            if (archiveWrapped.containsKey(newUid)) continue;
            final entry = await _wrapKeyFor(
              meUid: meUid,
              otherUid: newUid,
              sessionKeyBytes: archiveKeyBytes,
            );
            if (entry != null) {
              archiveWrapped[newUid] = entry;
              changed = true;
            }
          }
          if (changed) {
            archiveUpdate['wrappedKeysArchive.$versionStr'] = archiveWrapped;
            debugPrint(
                '[e2ee-rotate] backfilled archive v$versionStr for $newParticipants');
          }
        }
      }
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
    if (key != null) {
      _cacheKey(chatId, version, key);
    }
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
  Future<Set<String>> _wrappableParticipants(
      List<String> participantUids) async {
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
    // Try device key wrapping first
    final ct = wrappedFromMe['ct'];
    final n = wrappedFromMe['n'];
    final wrapperPubB64 = wrappedFromMe['kPub'];

    if (ct is String && n is String && wrapperPubB64 is String) {
      final myPriv = await _keys.readPrivateKeyBytes(meUid);
      if (myPriv != null) {
        final result = await _unwrapWithPrivateKey(
          meUid: meUid,
          privKeyBytes: myPriv,
          ct: ct,
          n: n,
          wrapperPubB64: wrapperPubB64,
          info: 'coil-e2ee-kek-v1',
        );
        if (result != null) return result;
      }
    }

    // Fallback: try recovery key wrapping if cached
    final recoveryWrapped = wrappedFromMe['recoveryWrapped'];
    if (recoveryWrapped is Map<String, dynamic>) {
      final rct = recoveryWrapped['ct'];
      final rn = recoveryWrapped['n'];
      final rwrapperPubB64 = recoveryWrapped['kPub'];

      if (rct is String && rn is String && rwrapperPubB64 is String) {
        final cachedRecovery = _recoveryKeyCache[meUid];
        if (cachedRecovery != null) {
          final result = await _unwrapWithPrivateKey(
            meUid: meUid,
            privKeyBytes: cachedRecovery,
            ct: rct,
            n: rn,
            wrapperPubB64: rwrapperPubB64,
            info: 'coil-e2ee-recovery-kek-v1',
          );
          if (result != null) {
            return result;
          }
        }
      }
    }

    return null;
  }

  Future<SecretKey?> _unwrapWithPrivateKey({
    required String meUid,
    required Uint8List privKeyBytes,
    required String ct,
    required String n,
    required String wrapperPubB64,
    required String info,
  }) async {
    try {
      final wrapperPub = SimplePublicKey(
        base64Decode(wrapperPubB64),
        type: KeyPairType.x25519,
      );

      final myPair = await _x25519.newKeyPairFromSeed(privKeyBytes);
      final shared = await _x25519.sharedSecretKey(
        keyPair: myPair,
        remotePublicKey: wrapperPub,
      );
      final kek = await _hkdf.deriveKey(
        secretKey: shared,
        info: utf8.encode(info),
        nonce: const [],
      );
      final clear = await _aesDecrypt(
        kek,
        ciphertext: base64Decode(ct),
        nonce: base64Decode(n),
      );
      return SecretKey(clear);
    } catch (_) {
      return null;
    }
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
      'rPub': base64Encode(otherPub
          .bytes), // recipient's pub key used; lets us detect key rotation
      'alg': 'X25519+AES-GCM-256',
    };
  }

  /// Wraps the session key for a participant's recovery public key.
  /// Used for cross-device decryption — a user can decrypt messages on a new
  /// device by recovering their backup key with their password.
  Future<Map<String, dynamic>?> _wrapKeyForRecovery({
    required String meUid,
    required String participantUid,
    required SimplePublicKey recoveryPublicKey,
    required List<int> sessionKeyBytes,
  }) async {
    final myPriv = await _keys.readPrivateKeyBytes(meUid);
    if (myPriv == null) return null;

    final myPair = await _x25519.newKeyPairFromSeed(myPriv);
    final myPub = await myPair.extractPublicKey();

    final shared = await _x25519.sharedSecretKey(
      keyPair: myPair,
      remotePublicKey: recoveryPublicKey,
    );
    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode('coil-e2ee-recovery-kek-v1'),
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

  Future<Map<String, dynamic>> _aesEncrypt(
      SecretKey key, List<int> clear) async {
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
