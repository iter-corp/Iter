import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/model/post_model.dart';
import 'notification_service.dart';
import 'profanity_filter_service.dart';

class DiscussPostBlockedException implements Exception {
  final List<String> matchedWords;

  const DiscussPostBlockedException(this.matchedWords);

  @override
  String toString() =>
      'This discuss question contains blocked words and cannot be posted.';
}

class PostBlockedException implements Exception {
  final List<String> matchedWords;

  const PostBlockedException(this.matchedWords);

  @override
  String toString() =>
      'This post contains blocked words and cannot be published.';
}

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
  final ProfanityFilterService _profanityFilter = ProfanityFilterService();

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  Future<String> createPost({
    required String caption,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
    bool isPrivate = false,
    String? postPlaceName,
    String? postPlaceCity,
    double? postLat,
    double? postLng,
    bool postLocationExact = false,
  }) async {
    debugPrint('[PostService] createPost start '
        'images=${imageUrls.length} videos=${videoUrls.length} '
        'captionLen=${caption.length} isPrivate=$isPrivate '
        'hasLoc=${postLat != null && postLng != null}');
    if (videoUrls.isNotEmpty) {
      debugPrint('[PostService] videoUrls=$videoUrls');
    }

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[PostService] ABORT: no Firebase user');
      throw Exception('Not signed in');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final avatar = userDoc.data()?['avatarUrl'] as String?;
    debugPrint('[PostService] author uid=${user.uid} username=$username');

    final placeName = (postPlaceName ?? '').trim();
    final placeCity = (postPlaceCity ?? '').trim();
    final hasLocation = postLat != null && postLng != null;

    final moderationText = [caption.trim(), placeName, placeCity]
        .where((part) => part.isNotEmpty)
        .join('\n');
    final matches = await _profanityFilter.findMatches(moderationText);
    if (matches.isNotEmpty) {
      throw PostBlockedException(matches);
    }

    try {
      final ref = await _posts.add({
        'authorUid': user.uid,
        'authorUsername': username,
        'authorAvatar': avatar,
        'caption': caption,
        'imageUrls': imageUrls,
        'videoUrls': videoUrls,
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
      debugPrint('[PostService] post doc created id=${ref.id}');

      await _db.collection('users').doc(user.uid).update({
        'postsCount': FieldValue.increment(1),
      });
      debugPrint('[PostService] postsCount incremented for ${user.uid}');

      return ref.id;
    } catch (e, st) {
      debugPrint('[PostService] createPost FAILED: $e\n$st');
      rethrow;
    }
  }

  Future<void> reportPost({
    required Post post,
    required String reason,
    String details = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    if (user.uid == post.authorUid) {
      throw Exception('You cannot report your own post');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final reportId = '${post.id}_${user.uid}';
    final reportRef = _db.collection('postReports').doc(reportId);
    final existing = await reportRef.get();
    if (existing.exists) {
      throw Exception('You already reported this post');
    }

    final trimmedReason = reason.trim();
    final trimmedDetails = details.trim();

    await reportRef.set({
      'postId': post.id,
      'postAuthorUid': post.authorUid,
      'postAuthorUsername': post.authorUsername,
      'postAuthorAvatar': post.authorAvatar,
      'postCaption': post.caption,
      'reporterUid': user.uid,
      'reporterUsername': username,
      'reason': trimmedReason,
      if (trimmedDetails.isNotEmpty) 'details': trimmedDetails,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reportQaPost({
    required Post post,
    required String reason,
    String details = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    if (user.uid == post.authorUid) {
      throw Exception('You cannot report your own question');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final reportId = '${post.id}_${user.uid}';
    final reportRef = _db.collection('discussReports').doc(reportId);
    final existing = await reportRef.get();
    if (existing.exists) {
      throw Exception('You already reported this question');
    }

    final trimmedReason = reason.trim();
    final trimmedDetails = details.trim();

    await reportRef.set({
      'postId': post.id,
      'postAuthorUid': post.authorUid,
      'postAuthorUsername': post.authorUsername,
      'postAuthorAvatar': post.authorAvatar,
      'postCaption': post.caption,
      'reporterUid': user.uid,
      'reporterUsername': username,
      'reason': trimmedReason,
      if (trimmedDetails.isNotEmpty) 'details': trimmedDetails,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Post>> streamFeed({int limit = 50}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit * 4)
        .snapshots()
        .map((s) {
      // Keep Q&A threads out of the normal feed.
      final filtered = s.docs
          .where((d) => (d.data()['postType'] as String?) != 'qa')
          .map(Post.fromDoc)
          .toList();
      if (filtered.length <= limit) return filtered;
      return filtered.take(limit).toList();
    });
  }

  /// Creates a Q&A thread. The document is stored in the same `posts`
  /// collection but tagged with `postType: 'qa'` so it is only surfaced
  /// in the Q&A feed and never pollutes the regular feed.
  Future<String> createQaPost({
    required String question,
    String details = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final avatar = userDoc.data()?['avatarUrl'] as String?;

    // Store question + optional body as caption so the existing Post model
    // works without schema changes.
    final caption = details.trim().isEmpty
        ? question.trim()
        : '${question.trim()}\n${details.trim()}';

    final matches = await _profanityFilter.findMatches(caption);
    if (matches.isNotEmpty) {
      throw DiscussPostBlockedException(matches);
    }

    final ref = await _posts.add({
      'authorUid': user.uid,
      'authorUsername': username,
      'authorAvatar': avatar,
      'caption': caption,
      'imageUrls': <String>[],
      'likesCount': 0,
      'commentsCount': 0,
      'isPrivate': false,
      'postType': 'qa',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  /// Turns an existing feed/travel post into a Discuss (Q&A) topic.
  ///
  /// [question] is the user's own question about the post — it becomes
  /// the QA caption. `sourcePostId` records the original post so the
  /// Discuss thread can embed it as a compact card. Returns the new
  /// QA doc id.
  ///
  /// If the source post already has a Discuss topic, that existing
  /// topic's id is returned instead — preventing duplicates.
  Future<String> createQaPostFromPost(
    Post source, {
    required String question,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    // Reuse an existing Discuss topic for this post if one exists.
    final existing = await findDiscussTopicForPost(source.id);
    if (existing != null) return existing;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final avatar = userDoc.data()?['avatarUrl'] as String?;

    final caption = question.trim().isEmpty
        ? 'Discussion about a post'
        : question.trim();

    final ref = await _posts.add({
      'authorUid': user.uid,
      'authorUsername': username,
      'authorAvatar': avatar,
      'caption': caption,
      'imageUrls': <String>[],
      'likesCount': 0,
      'commentsCount': 0,
      'isPrivate': false,
      'postType': 'qa',
      'sourcePostId': source.id,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Tag the original post so its menu can switch to "View in Discuss".
    try {
      await _posts.doc(source.id).update({'discussTopicId': ref.id});
    } catch (_) {
      // Non-fatal: the lookup-by-sourcePostId path still works.
    }

    return ref.id;
  }

  /// Fetches a single post (regular or QA) by id, or null if missing.
  Future<Post?> getPostById(String postId) async {
    final snap = await _posts.doc(postId).get();
    if (!snap.exists) return null;
    return Post.fromDoc(snap);
  }

  /// Returns the subset of [postIds] whose answers (comments) contain
  /// [query] (case-insensitive substring).
  ///
  /// Firestore can't substring-search, so this fetches each post's
  /// comments and filters client-side. Lookups run in parallel and the
  /// input is expected to already be bounded (the visible Discuss
  /// list, ~80 posts) so the cost stays reasonable.
  Future<Set<String>> qaPostsWithMatchingAnswer(
    Iterable<String> postIds,
    String query,
  ) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return <String>{};

    final ids = postIds.toList();
    final results = await Future.wait(ids.map((id) async {
      try {
        final snap =
            await _db.collection('posts').doc(id).collection('comments').get();
        final hit = snap.docs.any((d) {
          final text = (d.data()['text'] as String? ?? '').toLowerCase();
          return text.contains(q);
        });
        return hit ? id : null;
      } catch (_) {
        return null;
      }
    }));

    return results.whereType<String>().toSet();
  }

  /// Returns the QA topic id created from [postId], or null if none.
  Future<String?> findDiscussTopicForPost(String postId) async {
    final snap = await _posts
        .where('postType', isEqualTo: 'qa')
        .where('sourcePostId', isEqualTo: postId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  /// Q&A feed is isolated from normal posts by requiring postType == 'qa'.
  /// We sort client-side to avoid composite-index requirements.
  Stream<List<Post>> streamQaFeed({int limit = 80}) {
    return _posts
        .where('postType', isEqualTo: 'qa')
        .limit(240)
        .snapshots()
        .map((s) {
      final out = s.docs.map(Post.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      if (out.length <= limit) return out;
      return out.take(limit).toList();
    });
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
      // Distance for every travel post that has place coords. The
      // previous gate only surfaced km on exact-located posts which
      // hid most cards in the feed.
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
          travelDistanceKm: km,
          travelDistanceLabel: _distanceLabel(km),
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
        .map((s) => s.docs
            .where((d) => (d.data()['postType'] as String?) != 'qa')
            .map(Post.fromDoc)
            .toList());
  }

  /// Questions asked by this user (Q&A-only posts authored by uid).
  Stream<List<Post>> streamUserQaAsked(String uid, {int limit = 120}) {
    return _posts
        .where('authorUid', isEqualTo: uid)
        .where('postType', isEqualTo: 'qa')
        .limit(limit)
        .snapshots()
        .map((s) {
      final out = s.docs.map(Post.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return out;
    });
  }

  /// Questions this user has answered (via comments on Q&A posts).
  Stream<List<Post>> streamUserQaAnswered(String uid, {int limit = 120}) {
    return _db
        .collectionGroup('comments')
        .where('authorUid', isEqualTo: uid)
        .limit(360)
        .snapshots()
        .asyncMap((snap) async {
      final topLevelComments = snap.docs
          .where((doc) => doc.data()['parentCommentId'] == null)
          .toList();

      final postIds = <String>{};
      for (final c in topLevelComments) {
        final postRef = c.reference.parent.parent;
        if (postRef != null) postIds.add(postRef.id);
      }

      if (postIds.isEmpty) return const <Post>[];

      final docs = await Future.wait(postIds.map((id) => _posts.doc(id).get()));
      final out = docs
          .where((d) => d.exists)
          .map((d) => MapEntry(d, d.data()))
          .where((pair) => (pair.value?['postType'] as String?) == 'qa')
          .map((pair) => Post.fromDoc(pair.key))
          .toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });

      if (out.length <= limit) return out;
      return out.take(limit).toList();
    });
  }

  Future<void> deletePost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final postRef = _posts.doc(postId);
    final snap = await postRef.get();
    final data = snap.data();
    if (data == null) return;

    final isQa = (data['postType'] as String?) == 'qa';
    await postRef.delete();

    if (!isQa) {
      await _db.collection('users').doc(uid).update({
        'postsCount': FieldValue.increment(-1),
      });
    }
  }

  /// Admin delete of a post. Properly decrements the post author's postsCount.
  Future<void> deletePostAsAdmin(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    final postRef = _posts.doc(postId);
    final snap = await postRef.get();
    final data = snap.data();
    if (data == null) return;

    final authorUid = data['authorUid'] as String?;
    final isQa = (data['postType'] as String?) == 'qa';

    await postRef.delete();

    if (authorUid != null && !isQa) {
      await _db.collection('users').doc(authorUid).update({
        'postsCount': FieldValue.increment(-1),
      });
    }
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

    bool didRepost = false;
    await _db.runTransaction((tx) async {
      final existing = await tx.get(userRepostRef);
      if (existing.exists) {
        didRepost = false;
        tx.delete(userRepostRef);
        tx.delete(postRepostRef);
      } else {
        didRepost = true;
        final data = {'createdAt': FieldValue.serverTimestamp()};
        tx.set(userRepostRef, data);
        tx.set(postRepostRef, data);
      }
    });

    // Notify the post's author. Best-effort — failures here mustn't
    // unwind the repost itself. Deterministic doc id keeps the
    // repost → un-repost → repost cycle to a single notification.
    try {
      final postSnap = await _posts.doc(postId).get();
      final authorUid = postSnap.data()?['authorUid'] as String?;
      if (authorUid != null && authorUid.isNotEmpty && authorUid != user.uid) {
        final notifId = 'repost_${user.uid}_$postId';
        if (didRepost) {
          await _notifications.upsertNotification(
            targetUid: authorUid,
            docId: notifId,
            type: 'repost',
            actorUid: user.uid,
            targetId: postId,
          );
        } else {
          await _notifications.removeNotificationById(authorUid, notifId);
        }
      }
    } catch (_) {
      // Swallow — repost succeeded; notifications are best-effort.
    }
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

  /// Live count of users who reposted this post. The post doc itself
  /// has no `repostsCount` field — counts are derived from the
  /// `posts/{id}/reposts` subcollection so they stay in sync with
  /// transactional add/remove in [toggleRepost].
  Stream<int> streamRepostsCount(String postId) {
    return _posts
        .doc(postId)
        .collection('reposts')
        .snapshots()
        .map((s) => s.docs.length);
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
