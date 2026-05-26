import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/comment_providers.dart';
import '../../providers/post_providers.dart';
import '../../theme/app_theme.dart';
import '../../services/comment_service.dart';
import '../../utils/media_cache.dart';
import '../model/post_model.dart';
import 'post_detail_screen.dart';

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
  final Set<String> _expandedAnswers = {};

  void _toggleAnswer(String answerId) {
    setState(() {
      if (_expandedAnswers.contains(answerId)) {
        _expandedAnswers.remove(answerId);
      } else {
        _expandedAnswers.add(answerId);
      }
    });
  }

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
            title: Text(context.t.qaThreadTitle),
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
                          context.t.qaCouldNotLoadAnswers(e),
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
                        // Always order by creation time, newest first.
                        // Likes / dislikes are editorial signals only —
                        // they never reorder the list, so a single
                        // dislike no longer drags an answer to the
                        // bottom.
                        return b.createdAt.compareTo(a.createdAt);
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
                          final expanded = _expandedAnswers.contains(answer.id);
                          return _AnswerBlock(
                            postId: post.id,
                            answer: answer,
                            replies: replies,
                            expanded: expanded,
                            highlighted: highlighted,
                            onToggleExpanded: () => _toggleAnswer(answer.id),
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

class _QuestionCard extends ConsumerWidget {
  final Post post;

  const _QuestionCard({required this.post});

  static const List<String> _reportReasons = [
    'Spam or scam',
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Nudity or sexual content',
    'Misinformation',
    'Something else',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = post.caption.trim();
    final lines = caption
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title =
        lines.isEmpty ? context.t.qaUntitledQuestion : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';
    final isQuestion = post.discussKind == 'question' ||
        (post.discussKind == null && title.contains('?'));
    final hasSourcePost =
        post.sourcePostId != null && post.sourcePostId!.isNotEmpty;
    // Only the question's author may edit it.
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final isAuthor = currentUid != null && currentUid == post.authorUid;
    final canReport = currentUid != null && currentUid != post.authorUid;

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
                      context.t.timeAgo(post.createdAt),
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
                child: Text(
                  isQuestion
                      ? context.t.homeQuestionLabel
                      : context.t.homeDiscussionLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7E3BE8),
                  ),
                ),
              ),
              // 3-dot menu for question actions.
              if (isAuthor || canReport)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz,
                        size: 20, color: context.textSecondary),
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      if (action == 'edit') {
                        _editQuestion(context, ref);
                      }
                      if (action == 'delete') {
                        _deleteQuestion(context, ref);
                      }
                      if (action == 'report') {
                        _reportQuestion(context, ref);
                      }
                    },
                    itemBuilder: (_) => [
                      if (isAuthor)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(context.t.qaEditQuestion),
                          ]),
                        ),
                      if (isAuthor)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Color(0xFFEF476F),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.t.homeDeleteQuestionMenu,
                              style:
                                  const TextStyle(color: Color(0xFFEF476F)),
                            ),
                          ]),
                        ),
                      if (canReport)
                        PopupMenuItem(
                          value: 'report',
                          child: Row(children: [
                            const Icon(
                              Icons.flag_outlined,
                              size: 18,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.t.homeReportQuestionMenu,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // ── The user's question — always shown on top ────────────
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
          // ── The discussed post — embedded as a compact card ──────
          if (hasSourcePost) ...[
            const SizedBox(height: 12),
            _EmbeddedPostCard(postId: post.sourcePostId!),
          ],
          // Answer count text removed — the "Answers (N)" badge below
          // the question card already shows the live count and is the
          // single source of truth. The duplicate header line was
          // pulling from the post doc's cached `commentsCount`, which
          // could be stale or negative on legacy posts.
        ],
      ),
    );
  }

  /// Opens a dialog letting the question's author edit the question
  /// text (stored as the QA post's caption).
  Future<void> _editQuestion(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: post.caption);
    final strings = context.t;
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(strings.qaEditQuestion),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: strings.qaEditQuestionHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, controller.text.trim()),
            child: Text(strings.save),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || newText == post.caption.trim()) {
      return;
    }
    try {
      await ref.read(postServiceProvider).updatePost(
            post.id,
            caption: newText,
          );
    } catch (_) {
      // Edit is best-effort; the thread re-streams on success.
    }
  }

  Future<void> _reportQuestion(BuildContext context, WidgetRef ref) async {
    final detailsCtrl = TextEditingController();
    var selectedReason = _reportReasons.first;

    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.cardBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.t.homeReportQuestionMenu,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.pop(sheetContext, false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Text(
                          context.t.homePickReasonQuestion,
                          style: TextStyle(color: context.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        ..._reportReasons.map(
                          (reason) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: reason,
                            groupValue: selectedReason,
                            onChanged: (value) {
                              if (value == null) return;
                              setSheetState(() => selectedReason = value);
                            },
                            title: Text(
                              reason,
                              style: TextStyle(color: context.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: detailsCtrl,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: context.t.homeExtraDetailsOptional,
                            filled: true,
                            fillColor: context.inputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: context.borderColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, false),
                                child: Text(context.t.cancel),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, true),
                                child: Text(context.t.homeSendReport),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (submitted != true) return;

      await ref.read(postServiceProvider).reportQaPost(
            post: post,
            reason: selectedReason,
            details: detailsCtrl.text,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeReportSentAdmins)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeCouldNotReportQuestion(e))),
      );
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => detailsCtrl.dispose());
    }
  }

  Future<void> _deleteQuestion(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t.homeDeleteQuestionTitle),
        content: Text(context.t.homeDeleteQuestionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.t.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(postServiceProvider).deletePost(post.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeQuestionDeleted)),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeCouldNotDelete(e))),
      );
    }
  }
}

/// Compact preview of the post a Discuss topic is about: author line,
/// image (if any) and caption, inside a tappable bordered card that
/// opens the full post.
class _EmbeddedPostCard extends ConsumerWidget {
  final String postId;

  const _EmbeddedPostCard({required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(singlePostProvider(postId));

    return postAsync.when(
      loading: () => Container(
        height: 70,
        decoration: BoxDecoration(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (src) {
        if (src == null) return const SizedBox.shrink();
        final hasImage = src.imageUrls.isNotEmpty;
        final cap = src.caption.trim();

        return Material(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(postId: src.id),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author line.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: context.purpleSoft,
                          backgroundImage: (src.authorAvatar != null &&
                                  src.authorAvatar!.isNotEmpty)
                              ? NetworkImage(src.authorAvatar!)
                              : null,
                          child: (src.authorAvatar == null ||
                                  src.authorAvatar!.isEmpty)
                              ? Icon(Icons.person,
                                  size: 13, color: context.textSecondary)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            src.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: context.textMuted),
                      ],
                    ),
                  ),
                  // Image (if any) — served from the shared media
                  // cache so it isn't re-fetched on every open.
                  if (hasImage)
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: CachedNetworkImage(
                        imageUrl: src.imageUrls.first,
                        cacheManager: MediaCache.images,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: context.borderColor),
                      ),
                    ),
                  // Caption.
                  if (cap.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Text(
                        cap,
                        maxLines: hasImage ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
          context.t.qaAnswersLabel,
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
  final VoidCallback onToggleExpanded;
  final bool expanded;
  final bool highlighted;

  const _AnswerBlock({
    required this.postId,
    required this.answer,
    required this.replies,
    required this.onReply,
    required this.onToggleExpanded,
    required this.expanded,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Answer cards: bumped from hairline border to a soft shadow +
    // tinted background so each card reads as its own surface in a
    // long thread, matching the share-recipient / notification card
    // design used elsewhere.
    return Container(
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF7E3BE8).withValues(alpha: 0.10)
            : context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF7E3BE8).withValues(alpha: 0.55)
              : context.borderColor.withValues(alpha: 0.6),
          width: highlighted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? const Color(0xFF7E3BE8).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: highlighted ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnswerRow(
                  comment: answer,
                  postId: postId,
                  onTap: replies.isNotEmpty ? onToggleExpanded : null,
                  trailingAction: replies.isNotEmpty
                      ? Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_outlined
                              : Icons.keyboard_arrow_down_outlined,
                          color: context.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                _AnswerReactionBar(
                  postId: postId,
                  answer: answer,
                  onReply: () => onReply(answer),
                  enabled: !answer.senderOnly,
                ),
                if (replies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      expanded
                          ? context.t.commentHideReplies
                          : '${context.t.viewComments} (${replies.length})',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (expanded && replies.isNotEmpty) ...[
            Container(
              margin: const EdgeInsetsDirectional.only(
                  start: 14, top: 6, end: 12, bottom: 10),
              padding: const EdgeInsetsDirectional.only(start: 10),
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
                                postId: postId,
                                trailingAction: null,
                              ),
                              const SizedBox(height: 4),
                              _AnswerReactionBar(
                                postId: postId,
                                answer: r,
                                onReply: () => onReply(r),
                                compact: true,
                                enabled: !r.senderOnly,
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
  final bool enabled;

  const _AnswerReactionBar({
    required this.postId,
    required this.answer,
    required this.onReply,
    this.compact = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return Text(
        'Visible only to you',
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFB00020),
        ),
      );
    }

    final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final service = ref.read(commentServiceProvider);

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
          SnackBar(content: Text(context.t.qaCouldNotSaveReaction(e))),
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
            activeColor: AppColors.purple,
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
        ],
      );
    }

    final myReactionAsync = ref.watch(userAnswerReactionProvider((
      postId: postId,
      commentId: answer.id,
      uid: uid,
    )));

    return myReactionAsync.when(
      data: (myReaction) {
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
              activeColor: AppColors.purple,
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
          ],
        );
      },
      loading: () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ReactionChip(
            icon: Icons.favorite_border,
            label: '${answer.helpfulCount}',
            active: false,
            activeColor: AppColors.purple,
            compact: compact,
            onTap: () => setReaction('heart'),
          ),
          _ReactionChip(
            icon: Icons.heart_broken_outlined,
            label: '${answer.unhelpfulCount}',
            active: false,
            activeColor: const Color(0xFF8A6A30),
            compact: compact,
            onTap: () => setReaction('broken'),
          ),
          _ReplyReactionChip(onTap: onReply, compact: compact),
        ],
      ),
      error: (_, __) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ReactionChip(
            icon: Icons.favorite_border,
            label: '${answer.helpfulCount}',
            active: false,
            activeColor: AppColors.purple,
            compact: compact,
            onTap: () => setReaction('heart'),
          ),
          _ReactionChip(
            icon: Icons.heart_broken_outlined,
            label: '${answer.unhelpfulCount}',
            active: false,
            activeColor: const Color(0xFF8A6A30),
            compact: compact,
            onTap: () => setReaction('broken'),
          ),
          _ReplyReactionChip(onTap: onReply, compact: compact),
        ],
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.reply_rounded,
              size: 13,
              color: Color(0xFF7E3BE8),
            ),
            const SizedBox(width: 6),
            Text(
              context.t.reply,
              style: const TextStyle(
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

class _AnswerRow extends ConsumerWidget {
  final Comment comment;
  final bool compact;
  final Widget? trailingAction;
  final VoidCallback? onTap;
  // Post id is needed to wire edit/delete back through CommentService
  // when the current user is the author of [comment]. Optional so the
  // existing call sites (reply rows that don't need the menu) keep
  // working unchanged.
  final String? postId;

  const _AnswerRow({
    required this.comment,
    this.compact = false,
    this.trailingAction,
    this.onTap,
    this.postId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final isAuthor =
        currentUid != null && currentUid == comment.authorUid;
    final canManage = isAuthor && postId != null;
    return InkWell(
      onTap: onTap ?? () => openUserProfile(context, uid: comment.authorUid),
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
                        context.t.timeAgo(comment.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  _AnswerAuthorMenu(
                    postId: postId!,
                    comment: comment,
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
                      color: comment.profanityFiltered
                          ? const Color(0xFFB00020)
                          : context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (comment.senderOnly)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Visible only to you',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB00020),
                  ),
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
                        context.t.commentReplyingTo(replyTo!),
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
                          ? context.t.qaWriteAnswerHint
                          : context.t.qaWriteReplyHint,
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
                      : Text(replyTo == null
                          ? context.t.post
                          : context.t.reply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-dot menu rendered only for the author of an answer/reply.
/// Lets them edit the text or delete the answer outright. UI gating is
/// enforced here; the [CommentService] methods don't re-check, so this
/// is the only entry point that exposes them in the QA UI.
class _AnswerAuthorMenu extends ConsumerWidget {
  final String postId;
  final Comment comment;
  const _AnswerAuthorMenu({required this.postId, required this.comment});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    // Full-screen editor instead of an AlertDialog — gives the user a
    // proper writing surface, a keyboard that doesn't fight the dialog
    // chrome, and matches how the original post editor works elsewhere.
    final updated = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _EditAnswerScreen(initialText: comment.text),
        fullscreenDialog: true,
      ),
    );
    if (updated == null || updated.isEmpty || updated == comment.text) return;
    final currentUid = ref.read(authStateProvider).value?.uid;
    try {
      await ref.read(commentServiceProvider).editComment(
            postId: postId,
            commentId: comment.id,
            newText: updated,
            // Sender-only (profanity-flagged) answers live in the
            // per-user `privateComments` subcollection. Pass the
            // flag + uid so the service writes to the right path —
            // otherwise the public-path update fails with a
            // permission error.
            senderOnly: comment.senderOnly,
            currentUid: currentUid,
          );
    } on ProfanityEditRejected {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.commentEditBlockedProfanity)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.commentDeleteTitle),
        content: Text(ctx.t.commentDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.t.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final currentUid = ref.read(authStateProvider).value?.uid;
    try {
      await ref.read(commentServiceProvider).deleteComment(
            postId: postId,
            commentId: comment.id,
            senderOnly: comment.senderOnly,
            currentUid: currentUid,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, size: 18, color: context.textSecondary),
      onSelected: (v) {
        if (v == 'edit') _edit(context, ref);
        if (v == 'delete') _delete(context, ref);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 10),
              Text(context.t.edit),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFEF476F)),
              const SizedBox(width: 10),
              Text(
                context.t.delete,
                style: const TextStyle(color: Color(0xFFEF476F)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-screen text editor used by the answer-author menu's Edit
/// action. Returns the new text via Navigator.pop when the user taps
/// Save, or null on cancel/back.
class _EditAnswerScreen extends StatefulWidget {
  final String initialText;
  const _EditAnswerScreen({required this.initialText});

  @override
  State<_EditAnswerScreen> createState() => _EditAnswerScreenState();
}

class _EditAnswerScreenState extends State<_EditAnswerScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: Text(context.t.edit),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              context.t.save,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFB05ECC),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: context.cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFB05ECC)),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ),
    );
  }
}
