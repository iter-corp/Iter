import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/comment_providers.dart';
import '../../theme/app_theme.dart';
import '../../services/comment_service.dart';
import '../model/post_model.dart';

class QaThreadScreen extends ConsumerStatefulWidget {
  final Post post;

  /// When set, this user's answers are pinned to the top of the list.
  final String? highlightAuthorUid;

  /// When set, this answer is pinned above all other answers.
  final String? highlightCommentId;

  const QaThreadScreen({
    super.key,
    required this.post,
    this.highlightAuthorUid,
    this.highlightCommentId,
  });

  @override
  ConsumerState<QaThreadScreen> createState() => _QaThreadScreenState();
}

class _ReplyTarget {
  final String parentCommentId;
  final String username;

  const _ReplyTarget({
    required this.parentCommentId,
    required this.username,
  });
}

class _QaThreadScreenState extends ConsumerState<QaThreadScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  _ReplyTarget? _replyTo;

  void _startReply(Comment target) {
    final parentId = target.parentCommentId ?? target.id;
    setState(() {
      _replyTo = _ReplyTarget(
        parentCommentId: parentId,
        username: target.authorUsername,
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    final text = _controller.text.trim();
    final user = ref.read(authStateProvider).value;
    if (text.isEmpty || user == null) return;

    final userDoc = ref.read(currentUserDocProvider).value;
    final username =
        userDoc?['username'] as String? ?? user.displayName ?? 'user';
    final avatar = userDoc?['avatarUrl'] as String?;
    final target = _replyTo;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await ref.read(commentServiceProvider).addComment(
            postId: widget.post.id,
            authorUid: user.uid,
            authorUsername: username,
            authorAvatar: avatar,
            text: text,
            parentCommentId: target?.parentCommentId,
            replyToUsername: target?.username,
          );
      if (mounted) {
        setState(() => _replyTo = null);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .snapshots(),
      builder: (context, snap) {
        final post = (snap.hasData && snap.data!.exists)
            ? Post.fromDoc(snap.data!)
            : widget.post;

        final commentsAsync = ref.watch(commentsProvider(post.id));

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Q&A Thread'),
            foregroundColor: context.textPrimary,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: commentsAsync.when(
                    loading: () => ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      children: [
                        _QuestionCard(post: post),
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                    error: (e, _) => ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      children: [
                        _QuestionCard(post: post),
                        const SizedBox(height: 18),
                        Text(
                          'Could not load answers: $e',
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ],
                    ),
                    data: (comments) {
                      final topAnswers =
                          comments.where((c) => !c.isReply).toList();
                      final pinUid = widget.highlightAuthorUid;
                      final pinCommentId = widget.highlightCommentId;
                      topAnswers.sort((a, b) {
                        // Pin a specific answer when provided.
                        if (pinCommentId != null) {
                          final aPin = a.id == pinCommentId ? 0 : 1;
                          final bPin = b.id == pinCommentId ? 0 : 1;
                          if (aPin != bPin) return aPin.compareTo(bPin);
                        }
                        // Pin the highlighted user's answers to the top.
                        if (pinUid != null) {
                          final aPin = a.authorUid == pinUid ? 0 : 1;
                          final bPin = b.authorUid == pinUid ? 0 : 1;
                          if (aPin != bPin) return aPin.compareTo(bPin);
                        }
                        final byHelpful =
                            b.helpfulCount.compareTo(a.helpfulCount);
                        if (byHelpful != 0) return byHelpful;
                        final byUnhelpful =
                            a.unhelpfulCount.compareTo(b.unhelpfulCount);
                        if (byUnhelpful != 0) return byUnhelpful;
                        return (b.createdAt).compareTo(a.createdAt);
                      });
                      final repliesByParent = <String, List<Comment>>{};
                      for (final c in comments) {
                        if (c.parentCommentId == null) continue;
                        repliesByParent
                            .putIfAbsent(c.parentCommentId!, () => [])
                            .add(c);
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                        itemCount: 2 + topAnswers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _QuestionCard(post: post);
                          }
                          if (index == 1) {
                            return _AnswersHeader(count: topAnswers.length);
                          }

                          final answer = topAnswers[index - 2];
                          final replies =
                              repliesByParent[answer.id] ?? const <Comment>[];
                          final highlighted = (pinCommentId != null &&
                                  answer.id == pinCommentId) ||
                              (pinUid != null && answer.authorUid == pinUid);
                          return _AnswerBlock(
                            postId: post.id,
                            answer: answer,
                            replies: replies,
                            highlighted: highlighted,
                            onReply: _startReply,
                          );
                        },
                      );
                    },
                  ),
                ),
                _AnswerComposer(
                  controller: _controller,
                  focusNode: _focusNode,
                  sending: _sending,
                  replyTo: _replyTo?.username,
                  onCancelReply: _cancelReply,
                  onSubmit: _submitAnswer,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Post post;

  const _QuestionCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final caption = post.caption.trim();
    final lines = caption
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title = lines.isEmpty ? 'Untitled question' : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: context.purpleSoft,
                backgroundImage:
                    post.authorAvatar != null && post.authorAvatar!.isNotEmpty
                        ? NetworkImage(post.authorAvatar!)
                        : null,
                child: (post.authorAvatar == null || post.authorAvatar!.isEmpty)
                    ? Icon(
                        Icons.person,
                        size: 16,
                        color: context.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorUsername,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.purpleSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Question',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7E3BE8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${post.commentsCount} answers',
            style: TextStyle(
              fontSize: 12,
              color: context.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswersHeader extends StatelessWidget {
  final int count;

  const _AnswersHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Answers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.inputFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnswerBlock extends ConsumerWidget {
  final String postId;
  final Comment answer;
  final List<Comment> replies;
  final void Function(Comment target) onReply;
  final bool highlighted;

  const _AnswerBlock({
    required this.postId,
    required this.answer,
    required this.replies,
    required this.onReply,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final canDelete = currentUid != null && currentUid == answer.authorUid;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF7E3BE8).withValues(alpha: 0.08)
            : context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF7E3BE8).withValues(alpha: 0.5)
              : context.borderColor,
          width: highlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnswerRow(
            comment: answer,
            trailingAction: canDelete
                ? _DeleteMenuButton(
                    compact: false,
                    onDelete: () async {
                      try {
                        await ref.read(commentServiceProvider).deleteComment(
                              postId: postId,
                              commentId: answer.id,
                            );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Could not delete answer: $e')),
                        );
                      }
                    },
                  )
                : null,
          ),
          const SizedBox(height: 6),
          _AnswerReactionBar(
            postId: postId,
            answer: answer,
            onReply: () => onReply(answer),
          ),
          if (replies.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(left: 14),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: context.borderColor),
                ),
              ),
              child: Column(
                children: replies
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _AnswerRow(
                                comment: r,
                                compact: true,
                                trailingAction: currentUid != null &&
                                        currentUid == r.authorUid
                                    ? _DeleteMenuButton(
                                        compact: true,
                                        onDelete: () async {
                                          try {
                                            await ref
                                                .read(commentServiceProvider)
                                                .deleteComment(
                                                  postId: postId,
                                                  commentId: r.id,
                                                );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Could not delete reply: $e'),
                                              ),
                                            );
                                          }
                                        },
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              _AnswerReactionBar(
                                postId: postId,
                                answer: r,
                                onReply: () => onReply(r),
                                compact: true,
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerReactionBar extends ConsumerWidget {
  final String postId;
  final Comment answer;
  final VoidCallback onReply;
  final bool compact;

  const _AnswerReactionBar({
    required this.postId,
    required this.answer,
    required this.onReply,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final service = ref.read(commentServiceProvider);
    final canDelete = uid != null && uid == answer.authorUid;

    Future<void> setReaction(String type) async {
      if (uid == null) return;
      try {
        await service.setAnswerReaction(
          postId: postId,
          commentId: answer.id,
          uid: uid,
          type: type,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reaction: $e')),
        );
      }
    }

    if (uid == null) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ReactionChip(
            icon: Icons.favorite_border,
            label: '${answer.helpfulCount}',
            active: false,
            activeColor: const Color(0xFFE54865),
            compact: compact,
            onTap: () {},
          ),
          _ReactionChip(
            icon: Icons.heart_broken_outlined,
            label: '${answer.unhelpfulCount}',
            active: false,
            activeColor: const Color(0xFF8A6A30),
            compact: compact,
            onTap: () {},
          ),
          _ReplyReactionChip(onTap: onReply, compact: compact),
          if (canDelete)
            _DeleteMenuButton(
              compact: compact,
              onDelete: () async {
                try {
                  await service.deleteComment(
                    postId: postId,
                    commentId: answer.id,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not delete reply: $e')),
                  );
                }
              },
            ),
        ],
      );
    }

    return StreamBuilder<String?>(
      stream: service
          .streamUserAnswerReaction(
            postId: postId,
            commentId: answer.id,
            uid: uid,
          )
          .handleError((_, __) {}),
      builder: (context, snapshot) {
        final myReaction = snapshot.data;
        final heartOn = myReaction == 'heart';
        final brokenOn = myReaction == 'broken';

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ReactionChip(
              icon: heartOn ? Icons.favorite : Icons.favorite_border,
              label: '${answer.helpfulCount}',
              active: heartOn,
              activeColor: const Color(0xFFE54865),
              compact: compact,
              onTap: () => setReaction('heart'),
            ),
            _ReactionChip(
              icon: brokenOn ? Icons.heart_broken : Icons.heart_broken_outlined,
              label: '${answer.unhelpfulCount}',
              active: brokenOn,
              activeColor: const Color(0xFF8A6A30),
              compact: compact,
              onTap: () => setReaction('broken'),
            ),
            _ReplyReactionChip(onTap: onReply, compact: compact),
            if (canDelete)
              _DeleteMenuButton(
                compact: compact,
                onDelete: () async {
                  try {
                    await service.deleteComment(
                      postId: postId,
                      commentId: answer.id,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not delete reply: $e')),
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _DeleteMenuButton extends StatelessWidget {
  final bool compact;
  final Future<void> Function() onDelete;

  const _DeleteMenuButton({
    required this.compact,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (value) async {
        if (value != 'delete') return;
        await onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete'),
        ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: context.inputFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(
          Icons.more_horiz,
          size: compact ? 14 : 16,
          color: context.textSecondary,
        ),
      ),
    );
  }
}

class _ReplyReactionChip extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const _ReplyReactionChip({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: context.purpleSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF7E3BE8).withValues(alpha: 0.25),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.reply_rounded,
              size: 13,
              color: Color(0xFF7E3BE8),
            ),
            SizedBox(width: 6),
            Text(
              'Reply',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7E3BE8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final bool compact;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? activeColor : context.textSecondary;
    final bg = active ? activeColor.withValues(alpha: 0.12) : context.inputFill;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.35)
                : context.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 14 : 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final Comment comment;
  final bool compact;
  final Widget? trailingAction;

  const _AnswerRow({
    required this.comment,
    this.compact = false,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openUserProfile(context, uid: comment.authorUid),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: compact ? 12 : 14,
                  backgroundColor: context.purpleSoft,
                  backgroundImage: comment.authorAvatar != null &&
                          comment.authorAvatar!.isNotEmpty
                      ? NetworkImage(comment.authorAvatar!)
                      : null,
                  child: (comment.authorAvatar == null ||
                          comment.authorAvatar!.isEmpty)
                      ? Icon(
                          Icons.person,
                          size: compact ? 12 : 14,
                          color: context.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          comment.authorUsername,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(comment.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingAction != null) ...[
                  const SizedBox(width: 4),
                  trailingAction!,
                ],
              ],
            ),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                children: [
                  if (comment.replyToUsername != null &&
                      comment.replyToUsername!.isNotEmpty)
                    TextSpan(
                      text: '@${comment.replyToUsername} ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  TextSpan(
                    text: comment.text,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      color: context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String? replyTo;
  final VoidCallback onCancelReply;
  final Future<void> Function() onSubmit;

  const _AnswerComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: context.inputFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to @$replyTo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onCancelReply,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: replyTo == null
                          ? 'Write your answer...'
                          : 'Write your reply...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: sending ? null : onSubmit,
                  child: sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(replyTo == null ? 'Post' : 'Reply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime? dt) {
  if (dt == null) return 'just now';
  final now = DateTime.now();
  final d = now.difference(dt);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat('MMM d, y').format(dt);
}
