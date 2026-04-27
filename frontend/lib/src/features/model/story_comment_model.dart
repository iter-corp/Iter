import 'package:cloud_firestore/cloud_firestore.dart';

class StoryComment {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToUsername;

  const StoryComment({
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

  factory StoryComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StoryComment(
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
  
