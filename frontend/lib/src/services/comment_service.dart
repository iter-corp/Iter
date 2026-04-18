import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';

class Comment {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToUsername;

  const Comment({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
    this.replyToUsername,
  });

  bool get isReply => parentCommentId != null;

  factory Comment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Comment(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorUsername: d['authorUsername'] as String? ?? 'unknown',
      authorAvatar: d['authorAvatar'] as String?,
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      parentCommentId: d['parentCommentId'] as String?,
      replyToUsername: d['replyToUsername'] as String?,
    );
  }
}

class CommentService {
  final _db = FirebaseFirestore.instance;
  final NotificationService _notifications = NotificationService();

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  DocumentReference<Map<String, dynamic>> _postRef(String postId) =>
      _db.collection('posts').doc(postId);

  Stream<List<Comment>> streamComments(String postId) {
    return _comments(postId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(Comment.fromDoc).toList());
  }

  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorUsername,
    String? authorAvatar,
    required String text,
    String? parentCommentId,
    String? replyToUsername,
  }) async {
    final commentRef = _comments(postId).doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      if (replyToUsername != null) 'replyToUsername': replyToUsername,
    });
    batch.update(_postRef(postId), {
      'commentsCount': FieldValue.increment(1),
    });
    await batch.commit();

    // Fire a reply notification to the parent commenter (not to self).
    if (parentCommentId != null) {
      try {
        final parentSnap =
            await _comments(postId).doc(parentCommentId).get();
        final parentAuthorUid =
            parentSnap.data()?['authorUid'] as String?;
        if (parentAuthorUid != null && parentAuthorUid != authorUid) {
          await _notifications.createNotification(
            targetUid: parentAuthorUid,
            type: 'reply',
            actorUid: authorUid,
            targetId: postId,
          );
        }
      } catch (_) {
        // Notification is best-effort — comment was already saved.
      }
    }
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    final batch = _db.batch();
    batch.delete(_comments(postId).doc(commentId));
    batch.update(_postRef(postId), {
      'commentsCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }
}
