import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// Custom sticker model
// ─────────────────────────────────────────────

class CustomStickerPack {
  final String id;
  final String name;
  final String ownerUid;
  final List<String> stickerUrls;
  final DateTime? createdAt;

  const CustomStickerPack({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.stickerUrls,
    this.createdAt,
  });

  factory CustomStickerPack.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return CustomStickerPack(
      id: doc.id,
      name: (d['name'] as String?) ?? 'My Stickers',
      ownerUid: (d['ownerUid'] as String?) ?? '',
      stickerUrls: List<String>.from(d['stickerUrls'] as List? ?? []),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class StickerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── Recent stickers (local) ───────────────────────────────

  static const String _recentKey = 'recent_stickers';
  static const int _maxRecent = 30;

  Future<List<String>> getRecentStickers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? [];
  }

  Future<void> addRecentSticker(String stickerUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? [];
    recent.remove(stickerUrl);
    recent.insert(0, stickerUrl);
    if (recent.length > _maxRecent) {
      recent.removeRange(_maxRecent, recent.length);
    }
    await prefs.setStringList(_recentKey, recent);
  }

  // ── Favorite stickers (local) ─────────────────────────────

  static const String _favKey = 'favorite_stickers';

  Future<List<String>> getFavoriteStickers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favKey) ?? [];
  }

  Future<void> toggleFavorite(String stickerUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favKey) ?? [];
    if (favs.contains(stickerUrl)) {
      favs.remove(stickerUrl);
    } else {
      favs.insert(0, stickerUrl);
    }
    await prefs.setStringList(_favKey, favs);
  }

  Future<bool> isFavorite(String stickerUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favKey) ?? [];
    return favs.contains(stickerUrl);
  }

  // ── Custom sticker packs (Firestore + Storage) ────────────

  /// Create a new custom sticker pack.
  Future<String> createCustomPack({
    required String uid,
    required String name,
  }) async {
    final ref = await _db.collection('users').doc(uid)
        .collection('stickerPacks').add({
      'name': name.trim(),
      'ownerUid': uid,
      'stickerUrls': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Upload a sticker image and add it to a custom pack.
  Future<String> uploadCustomSticker({
    required String uid,
    required String packId,
    required File imageFile,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'users/$uid/stickers/$packId/sticker_$stamp.webp';
    final ref = _storage.ref(storagePath);
    await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/webp'),
    );
    final url = await ref.getDownloadURL();

    // Add to the pack's sticker list.
    await _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .doc(packId)
        .update({
      'stickerUrls': FieldValue.arrayUnion([url]),
    });

    return url;
  }

  /// Delete a single sticker from a custom pack.
  Future<void> removeCustomSticker({
    required String uid,
    required String packId,
    required String stickerUrl,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .doc(packId)
        .update({
      'stickerUrls': FieldValue.arrayRemove([stickerUrl]),
    });
    // Best-effort delete from storage; ignore failures.
    try {
      await _storage.refFromURL(stickerUrl).delete();
    } catch (_) {}
  }

  /// Delete an entire custom pack.
  Future<void> deleteCustomPack({
    required String uid,
    required String packId,
  }) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .doc(packId)
        .get();
    if (doc.exists) {
      final urls =
          List<String>.from(doc.data()?['stickerUrls'] as List? ?? []);
      for (final url in urls) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    }
    await _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .doc(packId)
        .delete();
  }

  /// Permanently deletes EVERY custom sticker the user owns — the Firestore
  /// pack docs under `users/{uid}/stickerPacks` AND the underlying `.webp`
  /// files in Firebase Storage under `users/{uid}/stickers/`. Used by account
  /// self-delete so no sticker data or media is left behind.
  ///
  /// Best-effort per item: a failure on one file/pack is skipped rather than
  /// aborting the whole account deletion.
  Future<void> deleteAllStickers(String uid) async {
    // 1. Firestore: each pack stores its sticker file URLs in `stickerUrls`.
    //    Delete each referenced Storage object, then the pack doc itself.
    final packs = await _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .get();
    for (final pack in packs.docs) {
      final urls =
          List<String>.from(pack.data()['stickerUrls'] as List? ?? const []);
      for (final url in urls) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {
          // File already gone or URL unparsable — skip.
        }
      }
      await pack.reference.delete();
    }

    // 2. Storage sweep: catch any stray files under the user's sticker folder
    //    that weren't referenced by a pack doc (e.g. an upload that failed to
    //    update Firestore). Firebase has no folder-delete, so list + recurse.
    await _deleteStorageFolder(_storage.ref('users/$uid/stickers'));
  }

  /// Recursively deletes all items under [ref] in Firebase Storage. A missing
  /// folder simply yields an empty listing.
  Future<void> _deleteStorageFolder(Reference ref) async {
    try {
      final result = await ref.listAll();
      for (final item in result.items) {
        try {
          await item.delete();
        } catch (_) {}
      }
      for (final prefix in result.prefixes) {
        await _deleteStorageFolder(prefix);
      }
    } catch (_) {
      // Folder doesn't exist (user never made a sticker) — nothing to do.
    }
  }

  /// Stream all custom packs for a user.
  Stream<List<CustomStickerPack>> streamCustomPacks(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('stickerPacks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CustomStickerPack.fromDoc).toList());
  }
}

// ─────────────────────────────────────────────
// Riverpod providers
// ─────────────────────────────────────────────

final stickerServiceProvider = Provider<StickerService>((_) => StickerService());

final customStickerPacksProvider =
    StreamProvider.family<List<CustomStickerPack>, String>((ref, uid) {
  return ref.watch(stickerServiceProvider).streamCustomPacks(uid);
});
