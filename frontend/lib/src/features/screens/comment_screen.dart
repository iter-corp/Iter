import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

  const CommentScreen({super.key, required this.post});

  @override
  ConsumerState<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends ConsumerState<CommentScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  _ReplyTarget? _replyTo;
  final Set<String> _expandedParents = <String>{};

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
      if (list.length != widget.post.commentsCount) {
        FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.post.id)
            .update({'commentsCount': list.length}).catchError((_) {});
      }
    });

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
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Comments',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${commentsAsync.value?.length ?? widget.post.commentsCount}',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // Comment list
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (comments) {
                  if (comments.isEmpty) {
                    return Center(
                      child: Text('No comments yet. Be the first!',
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

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: tops.length,
                    itemBuilder: (context, i) {
                      final parent = tops[i];
                      final replies = repliesByParent[parent.id] ?? const [];
                      final expanded = _expandedParents.contains(parent.id);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CommentTile(
                            comment: parent,
                            post: widget.post,
                            onReply: () => _startReply(parent),
                          ),
                          if (replies.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 56),
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
                                                ? 'Hide replies'
                                                : 'View ${replies.length} '
                                                    '${replies.length == 1 ? "reply" : "replies"}',
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
                                      (r) => _CommentTile(
                                        comment: r,
                                        post: widget.post,
                                        onReply: () => _startReply(r),
                                      ),
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
                        'Replying to @${_replyTo!.username}',
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
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
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
                              ? 'Reply to @${_replyTo!.username}...'
                              : 'Add a comment...',
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

  const _CommentTile({
    required this.comment,
    required this.post,
    required this.onReply,
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
    final avatarRadius = comment.isReply ? 14.0 : 16.0;

    void openProfile() {
      if (isDeleted) return;
      openUserProfile(context, uid: comment.authorUid);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openProfile,
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundImage:
                  hasAvatar ? CachedNetworkImageProvider(avatar) : null,
              child: hasAvatar ? null : Icon(Icons.person, size: avatarRadius),
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
                      DateFormat('MMM d').format(comment.createdAt),
                      style: TextStyle(color: context.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: context.textPrimary),
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
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onReply,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          'Reply',
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
                await ref
                    .read(commentServiceProvider)
                    .deleteComment(postId: post.id, commentId: comment.id);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child:
                    Icon(Icons.close, size: 16, color: context.textSecondary),
              ),
            ),
        ],
      ),
    );
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

  String _labelOf(String code) =>
      kTranslateLanguages.firstWhere((l) => l.code == code,
          orElse: () => const TranslateLanguage('?', '?')).label;

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
                  'Translate to ${_labelOf(_target)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal chip strip — tap to change target language.
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kTranslateLanguages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final lang = kTranslateLanguages[i];
                  final selected = lang.code == _target;
                  return GestureDetector(
                    onTap: () => _selectLang(lang.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFB05ECC)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        lang.label,
                        style: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
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
                          Clipboard.setData(
                              ClipboardData(text: _translated!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Translation copied'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}