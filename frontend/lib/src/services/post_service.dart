import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/model/post_model.dart';
import 'notification_service.dart';

class TravelPlaceResult {
  final String name;
  final String city;
  final double? lat;
  final double? lng;

  const TravelPlaceResult({
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
  });
}

class PostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notifications = NotificationService();

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  Future<String> createPost({
    required String caption,
    List<String> imageUrls = const [],
    bool isPrivate = false,
    String? postPlaceName,
    String? postPlaceCity,
    double? postLat,
    double? postLng,
    bool postLocationExact = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final avatar = userDoc.data()?['avatarUrl'] as String?;

    final placeName = (postPlaceName ?? '').trim();
    final placeCity = (postPlaceCity ?? '').trim();
    final hasLocation = postLat != null && postLng != null;

    final ref = await _posts.add({
      'authorUid': user.uid,
      'authorUsername': username,
      'authorAvatar': avatar,
      'caption': caption,
      'imageUrls': imageUrls,
      'likesCount': 0,
      'commentsCount': 0,
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),
      if (placeName.isNotEmpty) 'postPlaceName': placeName,
      if (placeCity.isNotEmpty) 'postPlaceCity': placeCity,
      if (hasLocation)
        'postLocation': {
          'lat': postLat,
          'lng': postLng,
        },
      if (hasLocation) 'postLocationExact': postLocationExact,
      if (placeName.isNotEmpty || placeCity.isNotEmpty)
        'placeSearchKey': '$placeName $placeCity'.trim().toLowerCase(),
    });

    await _db.collection('users').doc(user.uid).update({
      'postsCount': FieldValue.increment(1),
    });

    return ref.id;
  }

  Stream<List<Post>> streamFeed({int limit = 50}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  double? _distanceKm({
    required double? aLat,
    required double? aLng,
    required double? bLat,
    required double? bLng,
  }) {
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return null;
    }
    const r = 6371.0;
    final dLat = _toRad(bLat - aLat);
    final dLng = _toRad(bLng - aLng);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_toRad(aLat)) * math.cos(_toRad(bLat)) * sinLng * sinLng;
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _toRad(double d) => d * math.pi / 180;

  String _distanceLabel(double? km) {
    if (km == null) return '';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  Future<Set<String>> _allowedAuthors(String uid) async {
    final following =
        await _db.collection('users').doc(uid).collection('following').get();
    return {uid, ...following.docs.map((d) => d.id)};
  }

  Future<List<Post>> _getTravelPostsLocal({
    String? placeQuery,
    double? currentLat,
    double? currentLng,
    int limit = 60,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];

    final query = (placeQuery ?? '').trim().toLowerCase();
    final allowed = await _allowedAuthors(uid);
    final snap =
        await _posts.orderBy('createdAt', descending: true).limit(350).get();

    final out = <Post>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final placeName = (data['postPlaceName'] as String? ?? '').trim();
      final placeCity = (data['postPlaceCity'] as String? ?? '').trim();
      final loc = data['postLocation'];
      final locMap = loc is Map ? loc : null;
      final lat = (locMap?['lat'] as num?)?.toDouble();
      final lng = (locMap?['lng'] as num?)?.toDouble();
      final isExact = (data['postLocationExact'] as bool?) ?? false;

      if (placeName.isEmpty || lat == null || lng == null) continue;

      final isPrivate = (data['isPrivate'] as bool?) ?? false;
      final authorUid = (data['authorUid'] as String?) ?? '';
      if (isPrivate && !allowed.contains(authorUid)) continue;

      final haystack =
          '$placeName $placeCity ${(data['placeSearchKey'] as String? ?? '')}'
              .toLowerCase();
      if (query.isNotEmpty && !haystack.contains(query)) continue;

      final base = Post.fromDoc(doc);
      final km = _distanceKm(
        aLat: currentLat,
        aLng: currentLng,
        bLat: lat,
        bLng: lng,
      );
      out.add(
        Post(
          id: base.id,
          authorUid: base.authorUid,
          authorUsername: base.authorUsername,
          authorAvatar: base.authorAvatar,
          caption: base.caption,
          imageUrls: base.imageUrls,
          likesCount: base.likesCount,
          commentsCount: base.commentsCount,
          isPrivate: base.isPrivate,
          createdAt: base.createdAt,
          postPlaceName: placeName,
          postPlaceCity: placeCity,
          postLat: lat,
          postLng: lng,
          postLocationExact: isExact,
          travelDistanceKm: isExact ? km : null,
          travelDistanceLabel: isExact ? _distanceLabel(km) : '',
        ),
      );

      if (out.length >= limit) break;
    }

    return out;
  }

  Future<List<TravelPlaceResult>> _searchTravelPlacesLocal({
    String query = '',
    int limit = 20,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];

    final q = query.trim().toLowerCase();
    final allowed = await _allowedAuthors(uid);
    final snap =
        await _posts.orderBy('createdAt', descending: true).limit(350).get();

    final dedup = <String>{};
    final out = <TravelPlaceResult>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final placeName = (data['postPlaceName'] as String? ?? '').trim();
      final placeCity = (data['postPlaceCity'] as String? ?? '').trim();
      final loc = data['postLocation'];
      final locMap = loc is Map ? loc : null;
      final lat = (locMap?['lat'] as num?)?.toDouble();
      final lng = (locMap?['lng'] as num?)?.toDouble();
      if (placeName.isEmpty || lat == null || lng == null) continue;

      final isPrivate = (data['isPrivate'] as bool?) ?? false;
      final authorUid = (data['authorUid'] as String?) ?? '';
      if (isPrivate && !allowed.contains(authorUid)) continue;

      final haystack =
          '$placeName $placeCity ${(data['placeSearchKey'] as String? ?? '')}'
              .toLowerCase();
      if (q.isNotEmpty && !haystack.contains(q)) continue;

      final key = '${placeName.toLowerCase()}|${placeCity.toLowerCase()}';
      if (dedup.contains(key)) continue;
      dedup.add(key);

      out.add(
        TravelPlaceResult(
          name: placeName,
          city: placeCity,
          lat: lat,
          lng: lng,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Travel feed. Runs entirely on the client against Firestore so it works
  /// on the Spark plan (no Cloud Functions / Blaze required).
  Future<List<Post>> getTravelPosts({
    String? placeQuery,
    double? currentLat,
    double? currentLng,
    int limit = 60,
  }) {
    return _getTravelPostsLocal(
      placeQuery: placeQuery,
      currentLat: currentLat,
      currentLng: currentLng,
      limit: limit,
    );
  }

  /// Travel place search. Client-side; works without Cloud Functions.
  Future<List<TravelPlaceResult>> searchTravelPlaces({
    String query = '',
    int limit = 20,
  }) {
    return _searchTravelPlacesLocal(query: query, limit: limit);
  }

  Stream<List<Post>> streamUserPosts(String uid) {
    return _posts
        .where('authorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  Future<void> deletePost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    await _posts.doc(postId).delete();
    await _db.collection('users').doc(uid).update({
      'postsCount': FieldValue.increment(-1),
    });
  }

  Future<void> updatePost(
    String postId, {
    String? caption,
    bool? isPrivate,
  }) async {
    final data = <String, dynamic>{};
    if (caption != null) data['caption'] = caption;
    if (isPrivate != null) data['isPrivate'] = isPrivate;
    if (data.isEmpty) return;
    await _posts.doc(postId).update(data);
  }

  Future<void> toggleLike(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final likeRef = _posts.doc(postId).collection('likes').doc(user.uid);
    final postRef = _posts.doc(postId);
    bool didLike = false;
    String? authorUid;

    await _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      authorUid = postSnap.data()?['authorUid'] as String?;

      final likeSnap = await tx.get(likeRef);
      if (likeSnap.exists) {
        didLike = false;
        tx.delete(likeRef);
        tx.update(postRef, {'likesCount': FieldValue.increment(-1)});
      } else {
        didLike = true;
        tx.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
        tx.update(postRef, {'likesCount': FieldValue.increment(1)});
      }
    });

    // Spark-only in-app notification — upsert/remove by deterministic ID so
    // repeated like/unlike cycles never create duplicate notifications.
    if (authorUid != null && authorUid != user.uid) {
      final notifId = 'like_${user.uid}_$postId';
      try {
        if (didLike) {
          await _notifications.upsertNotification(
            targetUid: authorUid!,
            docId: notifId,
            type: 'like',
            actorUid: user.uid,
            targetId: postId,
          );
        } else {
          await _notifications.removeNotificationById(authorUid!, notifId);
        }
      } catch (_) {}
    }
  }

  Stream<bool> streamIsLiked(String postId, {String? uid}) {
    final effectiveUid = uid ?? _auth.currentUser?.uid;
    if (effectiveUid == null) return Stream.value(false);
    return _posts
        .doc(postId)
        .collection('likes')
        .doc(effectiveUid)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> toggleRepost(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final userRepostRef =
        _db.collection('users').doc(user.uid).collection('reposts').doc(postId);
    final postRepostRef =
        _posts.doc(postId).collection('reposts').doc(user.uid);

    await _db.runTransaction((tx) async {
      final existing = await tx.get(userRepostRef);
      if (existing.exists) {
        tx.delete(userRepostRef);
        tx.delete(postRepostRef);
      } else {
        final data = {'createdAt': FieldValue.serverTimestamp()};
        tx.set(userRepostRef, data);
        tx.set(postRepostRef, data);
      }
    });
  }

  Stream<bool> streamIsReposted(String postId, {String? uid}) {
    final effectiveUid = uid ?? _auth.currentUser?.uid;
    if (effectiveUid == null) return Stream.value(false);
    return _db
        .collection('users')
        .doc(effectiveUid)
        .collection('reposts')
        .doc(postId)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> toggleSave(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final ref =
        _db.collection('users').doc(user.uid).collection('saved').doc(postId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Stream<bool> streamIsSaved(String postId, {String? uid}) {
    final effectiveUid = uid ?? _auth.currentUser?.uid;
    if (effectiveUid == null) return Stream.value(false);
    return _db
        .collection('users')
        .doc(effectiveUid)
        .collection('saved')
        .doc(postId)
        .snapshots()
        .map((s) => s.exists);
  }

  Stream<List<Post>> streamUserSaved(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('saved')
        .snapshots()
        .asyncMap((snap) async {
      final entries = snap.docs.toList();
      entries.sort((a, b) {
        final at = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      final posts = await Future.wait(entries.map((d) async {
        final postSnap = await _posts.doc(d.id).get();
        return postSnap.exists ? Post.fromDoc(postSnap) : null;
      }));
      return posts.whereType<Post>().toList();
    });
  }

  /// Streams posts that [uid] has reposted, most recent first.
  /// Expands the repost pointer docs into full Post objects.
  Stream<List<Post>> streamUserReposts(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('reposts')
        .snapshots()
        .asyncMap((snap) async {
      final entries = snap.docs.toList();
      entries.sort((a, b) {
        final at = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      final posts = await Future.wait(entries.map((d) async {
        final postSnap = await _posts.doc(d.id).get();
        return postSnap.exists ? Post.fromDoc(postSnap) : null;
      }));
      return posts.whereType<Post>().toList();
    });
  }
}
