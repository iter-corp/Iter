import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../screens/comment_screen.dart';
import '../widgets/post_card.dart';
import '../widgets/skeleton_loader.dart';

/// A standalone screen that displays a single post fetched by [postId].
/// When [highlightCommentId] is provided the comment sheet opens
/// automatically and scrolls to / highlights that comment.
/// When [openComments] is true the sheet opens even without a specific
/// comment id — used by `comment` / `reply` notifications so the user
/// lands on the comments view even if the legacy notification doc
/// lacks a `commentId`.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final String? highlightCommentId;
  final bool openComments;
  // Fallback for older `reply` / `comment` notifications written before
  // `commentId` was persisted: knowing WHO replied lets the comment
  // screen find their newest reply and highlight that.
  final String? highlightAuthorUid;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.highlightCommentId,
    this.openComments = false,
    this.highlightAuthorUid,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.highlightCommentId != null || widget.openComments) {
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
        highlightAuthorUid: widget.highlightAuthorUid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.t.post),
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
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SkeletonPostCard(isDetailed: true),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Text(
                context.t.postNotFound,
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
