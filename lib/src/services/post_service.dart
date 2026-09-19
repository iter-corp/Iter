import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/model/post_model.dart';
import 'api_client.dart';
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

class PostService {
  static const String _cachedFeedKey = 'offline_cached_feed_v1';
  static const String _cachedQaFeedKey = 'offline_cached_qa_feed_v1';

  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal() {
    _loadOfflineCache();
  }

  Future<void> _loadOfflineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final feedJson = prefs.getString(_cachedFeedKey);
      if (feedJson != null && feedJson.isNotEmpty) {
        final decoded = jsonDecode(feedJson);
        if (decoded is List && _cachedFeed.isEmpty) {
          _cachedFeed = decoded
              .whereType<Map<String, dynamic>>()
              .map((m) {
                _updatePostLocalState(m);
                return Post.fromJson(m);
              })
              .toList();
          if (_cachedFeed.isNotEmpty) {
            _feedController.add(_cachedFeed);
          }
        }
      }

      final qaJson = prefs.getString(_cachedQaFeedKey);
      if (qaJson != null && qaJson.isNotEmpty) {
        final decoded = jsonDecode(qaJson);
        if (decoded is List && _cachedQaFeed.isEmpty) {
          _cachedQaFeed = decoded
              .whereType<Map<String, dynamic>>()
              .map((m) {
                _updatePostLocalState(m);
                return Post.fromJson(m);
              })
              .toList();
          if (_cachedQaFeed.isNotEmpty) {
            _qaFeedController.add(_cachedQaFeed);
          }
        }
      }
    } catch (e) {
      debugPrint('[PostService] _loadOfflineCache error: $e');
    }
  }

  Future<void> _saveOfflineCache(String key, List rawList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(rawList));
    } catch (_) {}
  }

  List<Post> get cachedFeed => List.unmodifiable(_cachedFeed);
  List<Post> get cachedQaFeed => List.unmodifiable(_cachedQaFeed);

  final ProfanityFilterService _profanityFilter = ProfanityFilterService();

  // Local reactive caches for likes, saves, reposts, and counts
  final Map<String, StreamController<bool>> _likeControllers = {};
  final Map<String, bool> _likeState = {};

  final Map<String, StreamController<bool>> _repostControllers = {};
  final Map<String, bool> _repostState = {};

  final Map<String, StreamController<int>> _repostCountControllers = {};
  final Map<String, int> _repostCounts = {};

  final Map<String, StreamController<bool>> _saveControllers = {};
  final Map<String, bool> _saveState = {};

  // Broadcast stream controller for global feeds
  final StreamController<List<Post>> _feedController =
      StreamController<List<Post>>.broadcast();
  final StreamController<List<Post>> _qaFeedController =
      StreamController<List<Post>>.broadcast();

  List<Post> _cachedFeed = [];
  List<Post> _cachedQaFeed = [];

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
    final placeName = (postPlaceName ?? '').trim();
    final placeCity = (postPlaceCity ?? '').trim();

    final moderationText = [caption.trim(), placeName, placeCity]
        .where((part) => part.isNotEmpty)
        .join('\n');
    final matches = await _profanityFilter.findMatches(moderationText);
    if (matches.isNotEmpty) {
      throw PostBlockedException(matches);
    }

    final payload = {
      'caption': caption,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'isPrivate': isPrivate,
      'postPlaceName': placeName.isNotEmpty ? placeName : null,
      'postPlaceCity': placeCity.isNotEmpty ? placeCity : null,
      'postLocation': (postLat != null && postLng != null)
          ? {'lat': postLat, 'lng': postLng}
          : null,
      'postLocationExact': postLocationExact,
    };

    final res = await ApiClient.instance.post('/posts', body: payload);
    final postId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    // Invalidate/refresh feeds
    refreshFeed();
    return postId;
  }

  Future<String> createQaPost({
    required String question,
    String details = '',
    String discussKind = 'question',
  }) async {
    final caption = details.trim().isEmpty
        ? question.trim()
        : '${question.trim()}\n${details.trim()}';

    final matches = await _profanityFilter.findMatches(caption);
    if (matches.isNotEmpty) {
      throw DiscussPostBlockedException(matches);
    }

    final payload = {
      'question': question,
      'details': details,
      'discussKind': discussKind == 'discussion' ? 'discussion' : 'question',
    };

    final res = await ApiClient.instance.post('/posts/qa', body: payload);
    final postId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshQaFeed();
    return postId;
  }

  Future<String> createQaPostFromPost(
    Post source, {
    required String question,
    String details = '',
  }) async {
    final trimmedQuestion =
        question.trim().isEmpty ? 'Discussion about a post' : question.trim();
    final caption = details.trim().isEmpty
        ? trimmedQuestion
        : '$trimmedQuestion\n${details.trim()}';

    final matches = await _profanityFilter.findMatches(caption);
    if (matches.isNotEmpty) {
      throw DiscussPostBlockedException(matches);
    }

    final payload = {
      'question': trimmedQuestion,
      'details': details,
      'discussKind': 'discussion',
      'sourcePostId': source.id,
    };

    final res = await ApiClient.instance.post('/posts/qa', body: payload);
    final postId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshQaFeed();
    return postId;
  }

  Future<Post?> getPostById(String postId) async {
    try {
      final res = await ApiClient.instance.get('/posts/$postId');
      if (res is Map<String, dynamic>) {
        final post = Post.fromJson(res);
        _updatePostLocalState(res);
        return post;
      }
      return null;
    } catch (e) {
      debugPrint('[PostService] getPostById error: $e');
      return null;
    }
  }

  Stream<List<Post>> streamFeed({int limit = 50}) {
    refreshFeed(limit: limit);
    return _feedController.stream;
  }

  Future<void> refreshFeed({int limit = 50}) async {
    if (_cachedFeed.isNotEmpty) {
      _feedController.add(_cachedFeed);
    }
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {'limit': '$limit'});
      if (res is List) {
        _cachedFeed = res
            .whereType<Map<String, dynamic>>()
            .map((m) {
              _updatePostLocalState(m);
              return Post.fromJson(m);
            })
            .toList();
        _feedController.add(_cachedFeed);
        _saveOfflineCache(_cachedFeedKey, res);
      }
    } catch (e) {
      debugPrint('[PostService] refreshFeed error: $e');
      if (_cachedFeed.isNotEmpty) {
        _feedController.add(_cachedFeed);
      }
    }
  }

  Stream<List<Post>> streamQaFeed({int limit = 80}) {
    refreshQaFeed(limit: limit);
    return _qaFeedController.stream;
  }

  Future<void> refreshQaFeed({int limit = 80}) async {
    if (_cachedQaFeed.isNotEmpty) {
      _qaFeedController.add(_cachedQaFeed);
    }
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {
        'limit': '$limit',
        'type': 'qa',
      });
      if (res is List) {
        _cachedQaFeed = res
            .whereType<Map<String, dynamic>>()
            .map((m) {
              _updatePostLocalState(m);
              return Post.fromJson(m);
            })
            .toList();
        _qaFeedController.add(_cachedQaFeed);
        _saveOfflineCache(_cachedQaFeedKey, res);
      }
    } catch (e) {
      debugPrint('[PostService] refreshQaFeed error: $e');
      if (_cachedQaFeed.isNotEmpty) {
        _qaFeedController.add(_cachedQaFeed);
      }
    }
  }

  Stream<List<Post>> streamUserPosts(String uid) async* {
    List<Post> apiPosts = [];
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {'authorUid': uid});
      if (res is List) {
        apiPosts = res
            .whereType<Map<String, dynamic>>()
            .map((m) {
              _updatePostLocalState(m);
              return Post.fromJson(m);
            })
            .toList();
        if (apiPosts.isNotEmpty) {
          yield apiPosts;
        }
      }
    } catch (e) {
      debugPrint('[PostService] streamUserPosts API error: $e');
    }

    yield* FirebaseFirestore.instance
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .snapshots()
        .map((s) {
          final firestorePosts = s.docs.map(Post.fromDoc).toList();
          final map = <String, Post>{};
          for (final p in apiPosts) {
            map[p.id] = p;
          }
          for (final p in firestorePosts) {
            map[p.id] = p;
          }
          final list = map.values.toList()
            ..sort((a, b) {
              final at = a.createdAt ?? DateTime(0);
              final bt = b.createdAt ?? DateTime(0);
              return bt.compareTo(at);
            });
          return list;
        })
        .handleError((e) {
          debugPrint('[PostService] Firestore streamUserPosts error: $e');
        });
  }

  Stream<List<Post>> streamUserQaAsked(String uid, {int limit = 120}) async* {
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {
        'authorUid': uid,
        'type': 'qa',
        'limit': '$limit',
      });
      if (res is List) {
        yield res
            .whereType<Map<String, dynamic>>()
            .map(Post.fromJson)
            .toList();
      } else {
        yield <Post>[];
      }
    } catch (_) {
      yield <Post>[];
    }
  }

  Stream<List<Post>> streamUserQaAnswered(String uid, {int limit = 120}) async* {
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {
        'answeredBy': uid,
        'limit': '$limit',
      });
      if (res is List) {
        yield res
            .whereType<Map<String, dynamic>>()
            .map(Post.fromJson)
            .toList();
      } else {
        yield <Post>[];
      }
    } catch (_) {
      yield <Post>[];
    }
  }

  Future<void> deletePost(String postId) async {
    await ApiClient.instance.delete('/posts/$postId');
    refreshFeed();
    refreshQaFeed();
  }

  Future<void> deletePostAsAdmin(String postId) async {
    await deletePost(postId);
  }

  Future<void> updatePost(
    String postId, {
    String? caption,
    bool? isPrivate,
  }) async {
    final payload = <String, dynamic>{};
    if (caption != null) payload['caption'] = caption;
    if (isPrivate != null) payload['isPrivate'] = isPrivate;
    if (payload.isEmpty) return;

    await ApiClient.instance.patch('/posts/$postId', body: payload);
    refreshFeed();
  }

  Future<void> toggleLike(String postId) async {
    final res = await ApiClient.instance.post('/posts/$postId/like');
    if (res is Map<String, dynamic> && res.containsKey('liked')) {
      final liked = res['liked'] == true;
      _likeState[postId] = liked;
      _likeControllers[postId]?.add(liked);
    }
  }

  Stream<bool> streamIsLiked(String postId, {String? uid}) {
    if (!_likeControllers.containsKey(postId) || _likeControllers[postId]!.isClosed) {
      _likeControllers[postId] = StreamController<bool>.broadcast();
    }
    if (_likeState.containsKey(postId)) {
      Timer.run(() => _likeControllers[postId]?.add(_likeState[postId]!));
    }
    return _likeControllers[postId]!.stream;
  }

  Future<void> toggleRepost(String postId) async {
    final res = await ApiClient.instance.post('/posts/$postId/repost');
    if (res is Map<String, dynamic> && res.containsKey('reposted')) {
      final reposted = res['reposted'] == true;
      _repostState[postId] = reposted;
      _repostControllers[postId]?.add(reposted);

      final currentCount = _repostCounts[postId] ?? 0;
      final newCount = reposted ? currentCount + 1 : (currentCount > 0 ? currentCount - 1 : 0);
      _repostCounts[postId] = newCount;
      _repostCountControllers[postId]?.add(newCount);
    }
  }

  Stream<bool> streamIsReposted(String postId, {String? uid}) {
    if (!_repostControllers.containsKey(postId) || _repostControllers[postId]!.isClosed) {
      _repostControllers[postId] = StreamController<bool>.broadcast();
    }
    if (_repostState.containsKey(postId)) {
      Timer.run(() => _repostControllers[postId]?.add(_repostState[postId]!));
    }
    return _repostControllers[postId]!.stream;
  }

  Stream<int> streamRepostsCount(String postId) {
    if (!_repostCountControllers.containsKey(postId) || _repostCountControllers[postId]!.isClosed) {
      _repostCountControllers[postId] = StreamController<int>.broadcast();
    }
    if (_repostCounts.containsKey(postId)) {
      Timer.run(() => _repostCountControllers[postId]?.add(_repostCounts[postId]!));
    }
    return _repostCountControllers[postId]!.stream;
  }

  Stream<List<String>> streamRepostUserIds(String postId) async* {
    yield <String>[];
  }

  Future<void> toggleSave(String postId) async {
    final res = await ApiClient.instance.post('/posts/$postId/save');
    if (res is Map<String, dynamic> && res.containsKey('saved')) {
      final saved = res['saved'] == true;
      _saveState[postId] = saved;
      _saveControllers[postId]?.add(saved);
    }
  }

  Stream<bool> streamIsSaved(String postId, {String? uid}) {
    if (!_saveControllers.containsKey(postId) || _saveControllers[postId]!.isClosed) {
      _saveControllers[postId] = StreamController<bool>.broadcast();
    }
    if (_saveState.containsKey(postId)) {
      Timer.run(() => _saveControllers[postId]?.add(_saveState[postId]!));
    }
    return _saveControllers[postId]!.stream;
  }

  Stream<List<Post>> streamUserSaved(String uid) async* {
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {'saved': 'true'});
      if (res is List) {
        yield res.whereType<Map<String, dynamic>>().map(Post.fromJson).toList();
      } else {
        yield <Post>[];
      }
    } catch (_) {
      yield <Post>[];
    }
  }

  Stream<List<Post>> streamUserReposts(String uid) async* {
    try {
      final res = await ApiClient.instance.get('/posts', queryParams: {'repostedBy': uid});
      if (res is List) {
        yield res.whereType<Map<String, dynamic>>().map(Post.fromJson).toList();
      } else {
        yield <Post>[];
      }
    } catch (_) {
      yield <Post>[];
    }
  }

  Future<void> reportPost({
    required Post post,
    required String reason,
    String details = '',
  }) async {
    await ApiClient.instance.post('/posts/${post.id}/report', body: {
      'reason': reason.trim(),
      'details': details.trim(),
    });
  }

  Future<void> reportQaPost({
    required Post post,
    required String reason,
    String details = '',
  }) =>
      reportPost(post: post, reason: reason, details: details);

  Future<Set<String>> qaPostsWithMatchingAnswer(
    Iterable<String> postIds,
    String query,
  ) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return <String>{};

    final matched = <String>{};
    for (final id in postIds) {
      try {
        final res = await ApiClient.instance.get('/comments/post/$id');
        if (res is List) {
          final hit = res.any((c) =>
              c is Map<String, dynamic> &&
              ((c['text'] as String?)?.toLowerCase().contains(q) ?? false));
          if (hit) matched.add(id);
        }
      } catch (_) {}
    }
    return matched;
  }

  void _updatePostLocalState(Map<String, dynamic> d) {
    final id = (d['id'] ?? d['postId']) as String?;
    if (id == null || id.isEmpty) return;

    if (d.containsKey('isLiked')) {
      final liked = d['isLiked'] == true;
      _likeState[id] = liked;
      _likeControllers[id]?.add(liked);
    }
    if (d.containsKey('isSaved')) {
      final saved = d['isSaved'] == true;
      _saveState[id] = saved;
      _saveControllers[id]?.add(saved);
    }
    if (d.containsKey('isReposted')) {
      final reposted = d['isReposted'] == true;
      _repostState[id] = reposted;
      _repostControllers[id]?.add(reposted);
    }
  }
}
