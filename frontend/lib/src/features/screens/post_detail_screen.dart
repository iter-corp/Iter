import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../model/post_model.dart';
import '../widgets/post_card.dart';

/// A standalone screen that displays a single post fetched by [postId].
/// Used when navigating from notifications where we only have the post ID.
class PostDetailScreen extends StatelessWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text(
                'Post not found',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          final post = Post.fromDoc(snap.data!);
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [PostCard(post: post)],
          );
        },
      ),
    );
  }
}
