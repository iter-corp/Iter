import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../screens/comment_screen.dart';
import '../widgets/post_card.dart';

/// A standalone screen that displays a single post fetched by [postId].
/// When [highlightCommentId] is provided the comment sheet opens automatically
/// and scrolls to / highlights that comment.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final String? highlightCommentId;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.highlightCommentId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.highlightCommentId != null) {
      _openCommentSheetWhenReady();
    }
  }

  Future<void> _openCommentSheetWhenReady() async {
    // Fetch the post immediately (uses Firestore cache when available).
    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .get();
    if (!mounted || !snap.exists) return;
    final post = Post.fromDoc(snap);

    // Wait for the push animation to finish (~300 ms) before showing the sheet.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CommentScreen(
        post: post,
        highlightCommentId: widget.highlightCommentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Post'),
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Text(
                'Post not found',
                style: TextStyle(color: context.textSecondary),
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
