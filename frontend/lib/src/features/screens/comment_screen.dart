import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../theme/app_theme.dart';
import '../../providers/comment_providers.dart';
import '../../navigation/user_profile_nav.dart';
import '../../services/comment_service.dart';
import '../../services/translate_service.dart';
import '../model/post_model.dart';

class _ReplyTarget {
  final String parentCommentId;
  final String username;
  const _ReplyTarget({
    required this.parentCommentId,
    required this.username,
  });
}

class CommentScreen extends ConsumerStatefulWidget {
  final Post post;
  final String? highlightCommentId;
  final bool showPostContext;
  // Fallback for legacy `reply` notifications that pre-date `commentId`:
  // when this is set and [highlightCommentId] is not, we look up the
  // newest comment whose `authorUid` matches and highlight it instead.
  final String? highlightAuthorUid;

  const CommentScreen({
    super.key,
    required this.post,
    this.highlightCommentId,
    this.showPostContext = false,
    this.highlightAuthorUid,
  });

  @override
  ConsumerState<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends ConsumerState<CommentScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  _ReplyTarget? _replyTo;
  final Set<String> _expandedParents = <String>{};
  final Map<String, GlobalKey> _commentKeys = {};
  bool _hasScrolledToHighlight = false;

  /// The id we still want to paint with the purple highlight band. Seeded
  /// from `widget.highlightCommentId` on first build and cleared after a
  /// 3-second cooldown so the user can register where the comment is
  /// without the highlight staying on forever.
  String? _activeHighlightId;
  bool _highlightSeeded = false;

  void _startReply(Comment parent) {
    // For replies-to-replies, still thread under the top-level parent so we
    // stay at a single nesting level (Instagram-style). Use the @username
    // prefix to show who is being addressed.
    final parentId = parent.parentCommentId ?? parent.id;
    setState(() {
      _replyTo = _ReplyTarget(
        parentCommentId: parentId,
        username: parent.authorUsername,
      );
      _expandedParents.add(parentId);
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  void _toggleReplies(String parentId) {
    setState(() {
      if (_expandedParents.contains(parentId)) {
        _expandedParents.remove(parentId);
      } else {
        _expandedParents.add(parentId);
      }
    });
  }

  Future<void> _submit() async {
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
      if (mounted) setState(() => _replyTo = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.post.id));

    // Silent backfill: if the post doc's cached commentsCount is wrong
    // (e.g. older posts from before client-side increment was wired), bring
    // it in sync with the actual comments subcollection length.
    commentsAsync.whenData((list) {
      final publicCount = list.where((c) => !c.senderOnly).length;
      if (publicCount != widget.post.commentsCount) {
        FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.post.id)
            .update({'commentsCount': publicCount}).catchError((_) {});
      }
    });

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final mq = MediaQuery.of(context);
        final composerBottomInset = (mq.viewInsets.bottom > 0
                ? mq.viewInsets.bottom
                : mq.padding.bottom) +
            12;

        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(
                    context.t.comments,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(commentsAsync.valueOrNull ?? const <Comment>[]).where((c) => !c.senderOnly).length}',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            if (widget.showPostContext)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: context.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  widget.post.caption.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),

            // Comment list
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(context.t.homeErrorPrefix(e))),
                data: (comments) {
                  if (comments.isEmpty) {
                    return Center(
                      child: Text(context.t.commentNoCommentsFirst,
                          style: TextStyle(color: context.textSecondary)),
                    );
                  }

                  final tops = comments.where((c) => !c.isReply).toList();
                  final repliesByParent = <String, List<Comment>>{};
                  for (final c in comments) {
                    if (c.parentCommentId != null) {
                      repliesByParent
                          .putIfAbsent(c.parentCommentId!, () => [])
                          .add(c);
                    }
                  }

                  // If a comment is highlighted, auto-expand its parent and
                  // scroll to it once after the list is first rendered.
                  // `_activeHighlightId` mirrors `widget.highlightCommentId`
                  // on first build and gets nulled out 3 seconds after the
                  // scroll-to fires so the purple band fades back to
                  // normal once the user has had a chance to see where the
                  // notification points.
                  // Resolve which comment to highlight. Prefer the
                  // explicit commentId from the notification doc;
                  // otherwise fall back to the newest comment / reply
                  // by the notifying actor (handles legacy
                  // notifications that pre-date `commentId` being
                  // persisted).
                  //
                  // We don't lock in the seed until we actually find a
                  // candidate — the first data snapshot can arrive
                  // empty (cache miss), and locking with `null` would
                  // block the fallback from ever firing once the real
                  // comments load on the next snapshot.
                  if (!_highlightSeeded) {
                    String? resolved = widget.highlightCommentId;
                    if (resolved == null &&
                        widget.highlightAuthorUid != null &&
                        widget.highlightAuthorUid!.isNotEmpty &&
                        comments.isNotEmpty) {
                      final authorMatches = comments
                          .where((c) =>
                              c.authorUid == widget.highlightAuthorUid)
                          .toList();
                      // Newest first.
                      authorMatches.sort(
                          (a, b) => b.createdAt.compareTo(a.createdAt));
                      if (authorMatches.isNotEmpty) {
                        resolved = authorMatches.first.id;
                      }
                    }
                    if (resolved != null) {
                      _highlightSeeded = true;
                      _activeHighlightId = resolved;
                    } else if (widget.highlightCommentId == null &&
                        widget.highlightAuthorUid == null) {
                      // No highlight target at all (e.g. opened from
                      // post tap rather than a notification). Lock the
                      // seed so the scroll-to / expand logic skips
                      // entirely on every rebuild.
                      _highlightSeeded = true;
                    }
                  }
                  final hid = _activeHighlightId;
                  final initialHid = _activeHighlightId;
                  if (initialHid != null && !_hasScrolledToHighlight) {
                    // If the highlighted comment is a reply, find its parent
                    // and expand that parent so the reply is visible.
                    final highlightedComment =
                        comments.where((c) => c.id == initialHid).firstOrNull;
                    if (highlightedComment != null &&
                        highlightedComment.isReply &&
                        !_expandedParents
                            .contains(highlightedComment.parentCommentId)) {
                      // Expand synchronously so the very next build of
                      // this ListView includes the reply row — that way
                      // the scroll-to retry below finds a real
                      // RenderObject instead of racing the expand.
                      _expandedParents
                          .add(highlightedComment.parentCommentId!);
                    }
                    _hasScrolledToHighlight = true; // prevent re-scheduling
                    // Retry the ensureVisible up to ~1s in 50ms chunks
                    // so we wait for the reply row to actually be built
                    // (the parent-expand setState produces a follow-up
                    // build; the row's GlobalKey only has a context
                    // after that build commits).
                    void tryScroll([int attempt = 0]) {
                      if (!mounted) return;
                      final key = _commentKeys[initialHid];
                      final ctx = key?.currentContext;
                      if (ctx != null) {
                        Scrollable.ensureVisible(
                          ctx,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          alignment: 0.3,
                        );
                        // Clear the purple band 3 s after the scroll
                        // has landed so the highlight doesn't stick
                        // forever.
                        Future.delayed(const Duration(seconds: 3), () {
                          if (!mounted) return;
                          setState(() => _activeHighlightId = null);
                        });
                        return;
                      }
                      if (attempt >= 20) return; // ~1 s total
                      Future.delayed(const Duration(milliseconds: 50),
                          () => tryScroll(attempt + 1));
                    }

                    Future.delayed(const Duration(milliseconds: 200),
                        tryScroll);
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: tops.length,
                    itemBuilder: (context, i) {
                      final parent = tops[i];
                      final replies = repliesByParent[parent.id] ?? const [];
                      final expanded = _expandedParents.contains(parent.id);
                      final parentKey = _commentKeys.putIfAbsent(
                          parent.id, () => GlobalKey());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CommentTile(
                            key: parentKey,
                            comment: parent,
                            post: widget.post,
                            onReply: () => _startReply(parent),
                            highlighted: hid == parent.id,
                          ),
                          if (replies.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(start: 56),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _toggleReplies(parent.id),
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 1,
                                            color: context.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            expanded
                                                ? context.t.commentHideReplies
                                                : '${context.t.viewComments} '
                                                    '(${replies.length})',
                                            style: TextStyle(
                                              color: context.textSecondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (expanded)
                                    ...replies.map(
                                      (r) {
                                        final replyKey =
                                            _commentKeys.putIfAbsent(
                                                r.id, () => GlobalKey());
                                        return _CommentTile(
                                          key: replyKey,
                                          comment: r,
                                          post: widget.post,
                                          onReply: () => _startReply(r),
                                          highlighted: hid == r.id,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // Reply target banner
            if (_replyTo != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: context.purpleSoft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t.commentReplyingTo(_replyTo!.username),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A3FB8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(Icons.close,
                          size: 16, color: context.textSecondary),
                    ),
                  ],
                ),
              ),

            // Input
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: composerBottomInset,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.inputFill,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: _replyTo != null
                              ? context.t
                                  .commentReplyToHint(_replyTo!.username)
                              : context.t.commentAddCommentHint,
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
  final VoidCallback onReply;
  final bool highlighted;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.post,
    required this.onReply,
    this.highlighted = false,
  });

  Future<void> _translateCommentToEnglish(BuildContext context) async {
    final raw = comment.text.trim();
    if (raw.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => _CommentTranslateSheet(text: raw),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final canDelete =
        currentUid == comment.authorUid || currentUid == post.authorUid;

    // Pull the author's current avatar/username from their user doc so
    // profile changes are reflected on old comments. When the doc has
    // loaded but is null the account was deleted — render "deleted user"
    // and disable navigation to the (now non-existent) profile.
    final liveAsync = ref.watch(userByUidProvider(comment.authorUid));
    final liveUser = liveAsync.value;
    final isDeleted = liveAsync.hasValue && liveUser == null;

    final avatar = isDeleted
        ? null
        : ((liveUser?['avatarUrl'] as String?) ?? comment.authorAvatar);
    final username = isDeleted
        ? 'deleted user'
        : ((liveUser?['username'] as String?) ?? comment.authorUsername);
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    final senderOnlyLabel = comment.senderOnly;
    final avatarRadius = comment.isReply ? 14.0 : 16.0;
    final commentService = ref.read(commentServiceProvider);
    final likesCountStream = commentService.streamCommentLikesCount(
      postId: post.id,
      commentId: comment.id,
    );
    final isLikedStream = currentUid == null
        ? Stream<bool>.value(false)
        : commentService.streamIsCommentLiked(
            postId: post.id,
            commentId: comment.id,
            uid: currentUid,
          );

    Future<void> onToggleLike() async {
      final uid = currentUid;
      if (uid == null) return;
      if (comment.senderOnly) return;
      await commentService.toggleLikeComment(
        postId: post.id,
        commentId: comment.id,
        uid: uid,
      );
    }

    void openProfile() {
      if (isDeleted) return;
      openUserProfile(context, uid: comment.authorUid);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF8A3FB8).withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: openProfile,
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundImage:
                    hasAvatar ? CachedNetworkImageProvider(avatar) : null,
                child:
                    hasAvatar ? null : Icon(Icons.person, size: avatarRadius),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: openProfile,
                        child: Text(
                          username,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontStyle:
                                isDeleted ? FontStyle.italic : FontStyle.normal,
                            color: isDeleted
                                ? context.textSecondary
                                : context.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d, h:mm a').format(comment.createdAt),
                        style:
                            TextStyle(color: context.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: comment.profanityFiltered
                            ? const Color(0xFFB00020)
                            : context.textPrimary,
                      ),
                      children: [
                        if (comment.replyToUsername != null &&
                            comment.replyToUsername!.isNotEmpty)
                          TextSpan(
                            text: '@${comment.replyToUsername} ',
                            style: const TextStyle(
                              color: Color(0xFF8A3FB8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        TextSpan(text: comment.text),
                      ],
                    ),
                  ),
                  if (senderOnlyLabel)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Visible only to you',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB00020),
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  if (!comment.senderOnly)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<bool>(
                          stream: isLikedStream,
                          builder: (context, likeSnap) {
                            final isLiked = likeSnap.data ?? false;
                            return GestureDetector(
                              onTap: onToggleLike,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      isLiked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 14,
                                      color: isLiked
                                          ? const Color(0xFFFF4D6D)
                                          : context.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    StreamBuilder<int>(
                                      stream: likesCountStream,
                                      builder: (context, countSnap) {
                                        final count = countSnap.data ?? 0;
                                        return Text(
                                          count > 0 ? '$count' : 'Like',
                                          style: TextStyle(
                                            color: isLiked
                                                ? const Color(0xFFFF4D6D)
                                                : context.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: onReply,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              context.t.reply,
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (comment.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () => _translateCommentToEnglish(context),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Translate',
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            if (canDelete)
              GestureDetector(
                onTap: () async {
                  await ref.read(commentServiceProvider).deleteComment(
                        postId: post.id,
                        commentId: comment.id,
                        senderOnly: comment.senderOnly,
                        currentUid: currentUid,
                      );
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child:
                      Icon(Icons.close, size: 16, color: context.textSecondary),
                ),
              ),
          ],
        ),
      ), // Padding
    ); // AnimatedContainer
  }
}

/// Bottom sheet that translates a comment and lets the user pick which
/// language to translate INTO. The translation re-runs whenever the user
/// taps a different language chip; the previous result is shown muted while
/// the next one loads so the sheet never appears empty mid-fetch.
class _CommentTranslateSheet extends StatefulWidget {
  final String text;
  const _CommentTranslateSheet({required this.text});

  @override
  State<_CommentTranslateSheet> createState() => _CommentTranslateSheetState();
}

class _CommentTranslateSheetState extends State<_CommentTranslateSheet> {
  String _target = 'en';
  String? _translated;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _translate();
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await const TranslateService().translateText(
        text: widget.text,
        sourceLang: 'auto',
        targetLang: _target,
      );
      if (!mounted) return;
      setState(() {
        _translated = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TranslateService.userFriendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _selectLang(String code) {
    if (code == _target) return;
    setState(() => _target = code);
    _translate();
  }

  String _labelOf(String code) => kTranslateLanguages
      .firstWhere((l) => l.code == code,
          orElse: () => const TranslateLanguage('?', '?'))
      .label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.t.commentTranslateTo(_labelOf(_target)),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal chip strip — tap to change target language.
            // Dedupe by translation code: kTranslateLanguages lists English
            // twice (USA / UK) for speech-to-text, but the translation API
            // treats them as one `en` so both chips would light up.
            SizedBox(
              height: 36,
              child: Builder(builder: (context) {
                final seen = <String>{};
                final chipLangs = <TranslateLanguage>[];
                for (final l in kTranslateLanguages) {
                  if (seen.add(l.code)) chipLangs.add(l);
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: chipLangs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final lang = chipLangs[i];
                    final selected = lang.code == _target;
                    final label = lang.code == 'en' ? 'English' : lang.label;
                    return GestureDetector(
                      onTap: () => _selectLang(lang.code),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFB05ECC)
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: selected ? Colors.white : null,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              SelectableText(
                _translated ?? '',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _translated == null || _loading
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _translated!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(context.t.commentTranslationCopied),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(context.t.copy),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
