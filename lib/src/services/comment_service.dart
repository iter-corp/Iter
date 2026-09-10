import 'dart:async';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'profanity_filter_service.dart';

class ProfanityEditRejected implements Exception {
  const ProfanityEditRejected();
  @override
  String toString() => 'ProfanityEditRejected';
}

class Comment {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToUsername;
  final int helpfulCount;
  final int unhelpfulCount;
  final int likesCount;
  final bool profanityFiltered;
  final bool senderOnly;
  final bool markedHelpful;

  const Comment({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
    this.replyToUsername,
    this.helpfulCount = 0,
    this.unhelpfulCount = 0,
    this.likesCount = 0,
    this.profanityFiltered = false,
    this.senderOnly = false,
    this.markedHelpful = false,
  });

  bool get isReply => parentCommentId != null;

  factory Comment.fromJson(Map<String, dynamic> d) {
    DateTime parsedCreated = DateTime.now();
    final rawCreated = d['createdAt'];
    if (rawCreated is String) {
      parsedCreated = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else if (rawCreated is int) {
      parsedCreated = DateTime.fromMillisecondsSinceEpoch(rawCreated);
    }

    return Comment(
      id: d['id'] as String? ?? '',
      authorUid: d['authorUid'] as String? ?? '',
      authorUsername: d['authorUsername'] as String? ?? 'unknown',
      authorAvatar: d['authorAvatar'] as String?,
      text: d['text'] as String? ?? '',
      createdAt: parsedCreated,
      parentCommentId: d['parentCommentId'] as String?,
      replyToUsername: d['replyToUsername'] as String?,
      helpfulCount: (d['helpfulCount'] as num?)?.toInt() ?? 0,
      unhelpfulCount: (d['unhelpfulCount'] as num?)?.toInt() ?? 0,
      likesCount: (d['likesCount'] as num?)?.toInt() ?? 0,
      profanityFiltered: d['profanityFiltered'] == true,
      senderOnly: d['senderOnly'] == true,
      markedHelpful: d['markedHelpful'] == true,
    );
  }
}

class CommentService {
  static final CommentService _instance = CommentService._internal();
  factory CommentService() => _instance;
  CommentService._internal();

  final ProfanityFilterService _profanityFilter = ProfanityFilterService();

  final Map<String, StreamController<List<Comment>>> _commentsControllers = {};
  final Map<String, List<Comment>> _commentsCache = {};

  final Map<String, StreamController<bool>> _likeControllers = {};
  final Map<String, bool> _likeState = {};

  Stream<List<Comment>> streamComments(String postId, {String? viewerUid}) {
    if (!_commentsControllers.containsKey(postId) || _commentsControllers[postId]!.isClosed) {
      _commentsControllers[postId] = StreamController<List<Comment>>.broadcast();
    }

    if (_commentsCache.containsKey(postId)) {
      Timer.run(() => _commentsControllers[postId]?.add(_commentsCache[postId]!));
    }

    refreshComments(postId);
    return _commentsControllers[postId]!.stream;
  }

  Stream<int> streamCommentsCount(String postId) {
    return streamComments(postId).map((list) => list.length);
  }

  Stream<int> streamCommentLikesCount({
    required String postId,
    required String commentId,
  }) {
    return Stream.value(0);
  }

  Stream<bool> streamIsCommentLiked({
    required String postId,
    required String commentId,
    required String uid,
  }) {
    return streamIsLiked(postId, commentId, uid: uid);
  }

  Future<void> toggleLikeComment({
    required String postId,
    required String commentId,
    required String uid,
  }) async {
    await toggleLike(postId, commentId);
  }

  Future<void> refreshComments(String postId) async {
    try {
      final res = await ApiClient.instance.get('/comments/post/$postId');
      if (res is List) {
        final list = res
            .whereType<Map<String, dynamic>>()
            .map((d) {
              if (d.containsKey('isLiked')) {
                final cId = d['id'] as String? ?? '';
                _likeState[cId] = d['isLiked'] == true;
                _likeControllers[cId]?.add(d['isLiked'] == true);
              }
              return Comment.fromJson(d);
            })
            .toList();

        _commentsCache[postId] = list;
        _commentsControllers[postId]?.add(list);
      }
    } catch (e) {
      debugPrint('[CommentService] refreshComments error: $e');
    }
  }

  Future<String> addComment({
    required String postId,
    required String text,
    String? parentCommentId,
    String? replyToUsername,
    String? authorUid,
    String? authorUsername,
    String? authorAvatar,
    bool senderOnly = false,
    String? currentUid,
  }) async {
    final payload = {
      'text': text.trim(),
      'parentCommentId': parentCommentId,
      'replyToUsername': replyToUsername,
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'senderOnly': senderOnly,
    };

    final res = await ApiClient.instance.post('/comments/post/$postId', body: payload);
    final commentId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshComments(postId);
    return commentId;
  }

  Future<void> editComment({
    required String postId,
    required String commentId,
    required String newText,
    bool senderOnly = false,
    String? currentUid,
  }) async {
    final matches = await _profanityFilter.findMatches(newText);
    if (matches.isNotEmpty) {
      throw const ProfanityEditRejected();
    }

    await ApiClient.instance.patch('/comments/$commentId', body: {'text': newText.trim()});
    refreshComments(postId);
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
    bool senderOnly = false,
    String? currentUid,
  }) async {
    await ApiClient.instance.delete('/comments/$commentId');
    refreshComments(postId);
  }

  Future<void> deleteCommentAsAdmin({
    required String postId,
    required String commentId,
  }) async {
    await ApiClient.instance.delete('/comments/$commentId');
    refreshComments(postId);
  }

  Future<void> reportComment({
    required String postId,
    required Comment comment,
    required String reason,
    required String details,
    String surface = 'comment',
  }) async {
    await ApiClient.instance.post('/comments/${comment.id}/report', body: {
      'postId': postId,
      'reason': reason,
      'details': details,
      'surface': surface,
    });
  }

  Stream<String?> streamUserAnswerReaction({
    required String postId,
    required String commentId,
    required String uid,
  }) {
    return Stream.value(null);
  }

  Future<void> setAnswerHelpful({
    required String postId,
    required String commentId,
    required bool helpful,
  }) async {
    await markHelpful(postId, commentId);
  }

  Future<void> setAnswerReaction({
    required String postId,
    required String commentId,
    required String uid,
    required String type,
  }) async {
    await voteHelpful(
      postId: postId,
      commentId: commentId,
      isHelpful: type == 'heart',
    );
  }

  Future<void> toggleLike(String postId, String commentId) async {
    final res = await ApiClient.instance.post('/comments/$commentId/like');
    if (res is Map<String, dynamic> && res.containsKey('liked')) {
      final liked = res['liked'] == true;
      _likeState[commentId] = liked;
      _likeControllers[commentId]?.add(liked);
    }
  }

  Stream<bool> streamIsLiked(String postId, String commentId, {String? uid}) {
    if (!_likeControllers.containsKey(commentId) || _likeControllers[commentId]!.isClosed) {
      _likeControllers[commentId] = StreamController<bool>.broadcast();
    }
    if (_likeState.containsKey(commentId)) {
      Timer.run(() => _likeControllers[commentId]?.add(_likeState[commentId]!));
    }
    return _likeControllers[commentId]!.stream;
  }

  Future<void> voteHelpful({
    required String postId,
    required String commentId,
    required bool isHelpful,
  }) async {
    await ApiClient.instance.post('/comments/$commentId/vote-helpful', body: {
      'isHelpful': isHelpful,
    });
    refreshComments(postId);
  }

  Future<void> markHelpful(String postId, String commentId) async {
    await ApiClient.instance.post('/comments/$commentId/mark-helpful');
    refreshComments(postId);
  }
}
