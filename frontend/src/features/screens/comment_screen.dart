import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_providers.dart';
import '../../providers/comment_providers.dart';
import '../../services/comment_service.dart';
import '../model/post_model.dart';

class CommentScreen extends ConsumerStatefulWidget {
  final Post post;

  const CommentScreen({super.key, required this.post});

  @override
  ConsumerState<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends ConsumerState<CommentScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  Future<void> _submit() async {
    final text = _controller.text.trim();
    final user = ref.read(authStateProvider).value;
    if (text.isEmpty || user == null) return;

    final userDoc = ref.read(currentUserDocProvider).value;
    final username =
        userDoc?['username'] as String? ?? user.displayName ?? 'user';
    final avatar = userDoc?['avatarUrl'] as String?;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await ref.read(commentServiceProvider).addComment(
            postId: widget.post.id,
            authorUid: user.uid,
            authorUsername: username,
            authorAvatar: avatar,
            text: text,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.post.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.post.commentsCount}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Comment list
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (comments) {
                  if (comments.isEmpty) {
                    return const Center(
                      child: Text('No comments yet. Be the first!',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: comments.length,
                    itemBuilder: (context, i) =>
                        _CommentTile(comment: comments[i], post: widget.post),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Input
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: _submit,
                          icon:
                              const Icon(Icons.send, color: Color(0xFFB05ECC)),
                        ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final Comment comment;
  final Post post;

  const _CommentTile({required this.comment, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final canDelete =
        currentUid == comment.authorUid || currentUid == post.authorUid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: (comment.authorAvatar?.isNotEmpty ?? false)
                ? CachedNetworkImageProvider(comment.authorAvatar!)
                : null,
            child: (comment.authorAvatar?.isEmpty ?? true)
                ? const Icon(Icons.person, size: 16)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorUsername,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MMM d').format(comment.createdAt),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (canDelete)
            GestureDetector(
              onTap: () async {
                await ref
                    .read(commentServiceProvider)
                    .deleteComment(postId: post.id, commentId: comment.id);
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
