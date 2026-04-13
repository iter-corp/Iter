import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Comment(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorUsername: d['authorUsername'] as String? ?? 'unknown',
      authorAvatar: d['authorAvatar'] as String?,
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class CommentService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

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
  }) async {
    final commentRef = _comments(postId).doc();
    await commentRef.set({
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    await _comments(postId).doc(commentId).delete();
  }
}
