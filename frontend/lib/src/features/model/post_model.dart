import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String caption;
  final List<String> imageUrls;
  final int likesCount;
  final int commentsCount;
  final bool isPrivate;
  final DateTime? createdAt;

  Post({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    required this.authorAvatar,
    required this.caption,
    required this.imageUrls,
    required this.likesCount,
    required this.commentsCount,
    required this.isPrivate,
    required this.createdAt,
  });

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return Post(
      id: d.id,
      authorUid: data['authorUid'] as String? ?? '',
      authorUsername: data['authorUsername'] as String? ?? 'unknown',
      authorAvatar: data['authorAvatar'] as String?,
      caption: data['caption'] as String? ?? '',
      imageUrls: (data['imageUrls'] as List?)?.cast<String>() ?? const [],
      likesCount: (data['likesCount'] as int?) ?? 0,
      commentsCount: (data['commentsCount'] as int?) ?? 0,
      isPrivate: (data['isPrivate'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
