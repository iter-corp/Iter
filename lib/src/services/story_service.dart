import 'dart:async';
import 'package:flutter/foundation.dart';

import '../features/model/story_comment_model.dart';
import '../features/widgets/story_text_overlay.dart';
import 'api_client.dart';

class Story {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String imageUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int likesCount;
  final int commentsCount;
  final String? sharedPostId;
  final String? sharedEventId;
  final String? sharedEventTitle;
  final String? videoUrl;
  final int? videoTrimStartMs;
  final int? videoTrimEndMs;
  final String? textContent;
  final int? backgroundColor;
  final int? textColor;
  final String? textBorderStyle;
  final List<StoryTextOverlay> overlays;

  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get isText =>
      (textContent != null && textContent!.trim().isNotEmpty) &&
      imageUrl.isEmpty &&
      (videoUrl == null || videoUrl!.isEmpty);

  Story({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharedPostId,
    this.sharedEventId,
    this.sharedEventTitle,
    this.videoUrl,
    this.videoTrimStartMs,
    this.videoTrimEndMs,
    this.textContent,
    this.backgroundColor,
    this.textColor,
    this.textBorderStyle,
    this.overlays = const [],
  });

  factory Story.fromJson(Map<String, dynamic> d) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }

    return Story(
      id: (d['id'] as String?) ?? '',
      authorUid: (d['authorUid'] as String?) ?? '',
      authorUsername: (d['authorUsername'] as String?) ?? '',
      authorAvatar: d['authorAvatar'] as String?,
      imageUrl: (d['imageUrl'] as String?) ?? '',
      createdAt: parseDate(d['createdAt']),
      expiresAt: parseDate(d['expiresAt']),
      likesCount: (d['likesCount'] as int?) ?? 0,
      commentsCount: (d['commentsCount'] as int?) ?? 0,
      sharedPostId: (d['sharedPostId'] as String?)?.trim(),
      sharedEventId: (d['sharedEventId'] as String?)?.trim(),
      sharedEventTitle: (d['sharedEventTitle'] as String?)?.trim(),
      videoUrl: (d['videoUrl'] as String?)?.trim(),
      videoTrimStartMs: (d['videoTrimStartMs'] as num?)?.toInt(),
      videoTrimEndMs: (d['videoTrimEndMs'] as num?)?.toInt(),
      textContent: (d['textContent'] as String?),
      backgroundColor: (d['backgroundColor'] as num?)?.toInt(),
      textColor: (d['textColor'] as num?)?.toInt(),
      textBorderStyle: (d['textBorderStyle'] as String?)?.trim(),
      overlays: ((d['overlays'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StoryTextOverlay.fromJson)
          .toList(growable: false),
    );
  }

  factory Story.fromDoc(dynamic doc) {
    if (doc == null) {
      return Story.fromJson({});
    }
    final rawData = (doc is Map<String, dynamic>)
        ? doc
        : (doc.data != null && doc.data() is Map<String, dynamic>
            ? (doc.data() as Map<String, dynamic>)
            : <String, dynamic>{});
    final map = Map<String, dynamic>.from(rawData);
    try {
      if (doc.id != null) {
        map['id'] = doc.id;
      }
    } catch (_) {}
    return Story.fromJson(map);
  }
}

class StoryViewer {
  final String uid;
  final String username;
  final String? avatarUrl;
  final DateTime? viewedAt;

  const StoryViewer({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.viewedAt,
  });

  factory StoryViewer.fromJson(Map<String, dynamic> d) {
    DateTime? vDate;
    final raw = d['viewedAt'];
    if (raw is String) vDate = DateTime.tryParse(raw);
    if (raw is int) vDate = DateTime.fromMillisecondsSinceEpoch(raw);

    return StoryViewer(
      uid: (d['uid'] as String?) ?? '',
      username: (d['username'] as String?) ?? '',
      avatarUrl: d['avatarUrl'] as String?,
      viewedAt: vDate,
    );
  }
}

class StoryService {
  static final StoryService _instance = StoryService._internal();
  factory StoryService() => _instance;
  StoryService._internal();

  final StreamController<List<Story>> _storiesController =
      StreamController<List<Story>>.broadcast();
  List<Story> _cachedStories = [];

  final Map<String, StreamController<bool>> _likeControllers = {};
  final Map<String, bool> _likeState = {};

  final Set<String> _viewedStories = {};

  Future<String> createStory({
    required String imageUrl,
    String? sharedPostId,
    String? sharedEventId,
    String? sharedEventTitle,
    String? videoUrl,
    int? videoTrimStartMs,
    int? videoTrimEndMs,
    String? textContent,
    int? backgroundColor,
    int? textColor,
    String? textBorderStyle,
    List<StoryTextOverlay> overlays = const [],
  }) async {
    final payload = {
      'imageUrl': imageUrl,
      'sharedPostId': sharedPostId,
      'sharedEventId': sharedEventId,
      'sharedEventTitle': sharedEventTitle,
      'videoUrl': videoUrl,
      'videoTrimStartMs': videoTrimStartMs,
      'videoTrimEndMs': videoTrimEndMs,
      'textContent': textContent,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'textBorderStyle': textBorderStyle,
      'overlays': overlays.map((o) => o.toJson()).toList(),
    };

    final res = await ApiClient.instance.post('/stories', body: payload);
    final storyId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshActiveStories();
    return storyId;
  }

  Stream<List<Story>> streamActiveStories() {
    refreshActiveStories();
    return _storiesController.stream;
  }

  Future<void> refreshActiveStories() async {
    try {
      final res = await ApiClient.instance.get('/stories/active');
      if (res is List) {
        _cachedStories = res
            .whereType<Map<String, dynamic>>()
            .map(Story.fromJson)
            .toList();
        _storiesController.add(_cachedStories);
      }
    } catch (e) {
      debugPrint('[StoryService] refreshActiveStories error: $e');
      if (_cachedStories.isNotEmpty) {
        _storiesController.add(_cachedStories);
      }
    }
  }

  Future<bool> hasViewed(String storyId) async {
    return _viewedStories.contains(storyId);
  }

  Future<void> deleteStory(String storyId) async {
    await ApiClient.instance.delete('/stories/$storyId');
    refreshActiveStories();
  }

  Future<void> recordView(String storyId, {required String authorUid}) async {
    _viewedStories.add(storyId);
    try {
      await ApiClient.instance.post('/stories/$storyId/view');
    } catch (_) {}
  }

  Stream<int> streamViewersCount(String storyId) async* {
    try {
      final res = await ApiClient.instance.get('/stories/$storyId/viewers');
      if (res is List) {
        yield res.length;
      } else {
        yield 0;
      }
    } catch (_) {
      yield 0;
    }
  }

  Stream<List<StoryViewer>> streamViewers(String storyId) async* {
    try {
      final res = await ApiClient.instance.get('/stories/$storyId/viewers');
      if (res is List) {
        yield res
            .whereType<Map<String, dynamic>>()
            .map(StoryViewer.fromJson)
            .toList();
      } else {
        yield <StoryViewer>[];
      }
    } catch (_) {
      yield <StoryViewer>[];
    }
  }

  Future<void> toggleLike(String storyId) async {
    final res = await ApiClient.instance.post('/stories/$storyId/like');
    if (res is Map<String, dynamic> && res.containsKey('liked')) {
      final liked = res['liked'] == true;
      _likeState[storyId] = liked;
      _likeControllers[storyId]?.add(liked);
    }
  }

  Stream<bool> streamIsLiked(String storyId, {String? uid}) {
    if (!_likeControllers.containsKey(storyId) || _likeControllers[storyId]!.isClosed) {
      _likeControllers[storyId] = StreamController<bool>.broadcast();
    }
    if (_likeState.containsKey(storyId)) {
      Timer.run(() => _likeControllers[storyId]?.add(_likeState[storyId]!));
    }
    return _likeControllers[storyId]!.stream;
  }

  Stream<int> streamLikesCount(String storyId) async* {
    yield 0;
  }

  Stream<List<StoryViewer>> streamLikers(String storyId) async* {
    yield <StoryViewer>[];
  }

  Future<void> addComment({
    required String storyId,
    required String authorUid,
    required String authorUsername,
    String? authorAvatar,
    required String text,
    String? parentCommentId,
    String? replyToUsername,
  }) async {
    // Can be forwarded to chat reply or comments
  }

  Stream<List<StoryComment>> streamComments(String storyId) async* {
    yield <StoryComment>[];
  }

  Future<void> deleteComment({
    required String storyId,
    required String commentId,
  }) async {}
}
