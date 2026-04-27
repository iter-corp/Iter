import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../screens/comment_screen.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/user_screen.dart';

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  // Optimistic UI: non-null while a like toggle is in-flight.
  bool? _pendingLike;

  // Carousel state for multi-image posts.
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final currentLiked =
        ref.read(isLikedProvider(widget.post.id)).value ?? false;
    if (_pendingLike != null) return; // already in-flight, ignore tap
    setState(() => _pendingLike = !currentLiked);
    try {
      await ref.read(postServiceProvider).toggleLike(widget.post.id);
    } finally {
      if (mounted) setState(() => _pendingLike = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isLikedAsync = ref.watch(isLikedProvider(post.id));
    // Use optimistic value while in-flight, otherwise use live stream value.
    final isLiked = _pendingLike ?? isLikedAsync.value ?? false;
    final isRepostedAsync = ref.watch(isRepostedProvider(post.id));
    final isReposted = isRepostedAsync.value ?? false;
    final isSaved = ref.watch(isSavedProvider(post.id)).value ?? false;
    final repostsEnabled =
        ref.watch(adminConfigProvider).valueOrNull?.repostsEnabled ?? true;
    final hasImage = post.imageUrls.isNotEmpty;
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final isOwner = currentUid != null && currentUid == post.authorUid;

    final imageCount = post.imageUrls.length;
    final isMulti = imageCount > 1;

    final isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: hasImage
                ? SizedBox(
                    height: 400,
                    width: double.infinity,
                    child: isMulti
                        ? PageView.builder(
                            controller: _pageController,
                            itemCount: imageCount,
                            onPageChanged: (i) =>
                                setState(() => _currentPage = i),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ImageViewerScreen(
                                    urls: post.imageUrls,
                                    initialIndex: i,
                                  ),
                                ),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: post.imageUrls[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImageViewerScreen(
                                  urls: post.imageUrls,
                                ),
                              ),
                            ),
                            child: CachedNetworkImage(
                              imageUrl: post.imageUrls.first,
                              fit: BoxFit.cover,
                            ),
                          ),
                  )
                : Container(
                    height: 400,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? const [Color(0xFF3A2F52), Color(0xFF23202E)]
                            : const [Color(0xFF3A2F52), Color(0xFF2B2D30)],
                      ),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
<<<<<<< Updated upstream
                    child: Text(
                      post.caption,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
=======
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ExpandableCaption(
                          text: post.caption,
                          collapsedMaxLines: 8,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                          toggleColor: Colors.white,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _translateCaption(context),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.translate,
                                  size: 14, color: Colors.white70),
                              SizedBox(width: 4),
                              Text(
                                'Translate',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
>>>>>>> Stashed changes
                    ),
                  ),
          ),
          if (hasImage)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (isOwner)
            Positioned(
              top: 12,
              right: 12,
              child: _OwnerMenu(post: post, ref: ref),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(uid: post.authorUid),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey.shade700,
                      backgroundImage: post.authorAvatar != null
                          ? CachedNetworkImageProvider(post.authorAvatar!)
                          : null,
                      child: post.authorAvatar == null
                          ? const Icon(Icons.person,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorUsername,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMulti) ...[
                  Center(
                    child:
                        _PageDots(count: imageCount, activeIndex: _currentPage),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? Colors.red : Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text('${post.likesCount}',
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: context.cardBg,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => CommentScreen(post: post),
                      ),
                      child: _miniIcon(
                          'assets/icons/Group.svg', '${post.commentsCount}'),
                    ),
                    if (repostsEnabled) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () =>
                            ref.read(postServiceProvider).toggleRepost(post.id),
                        child: Icon(
                          Icons.repeat,
                          color: isReposted
                              ? const Color(0xFFB05ECC)
                              : Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _openShareSheet(context, ref),
                      child: _miniIcon('assets/icons/Send.svg', ''),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () =>
                          ref.read(postServiceProvider).toggleSave(post.id),
                      child: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? const Color(0xFFB05ECC) : Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                if (hasImage && post.caption.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showFullCaption(context),
                    child: Text(
                      post.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullCaption(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
<<<<<<< Updated upstream
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: widget.post.authorAvatar != null
                          ? CachedNetworkImageProvider(
                              widget.post.authorAvatar!)
                          : null,
                      child: widget.post.authorAvatar == null
                          ? const Icon(Icons.person, size: 16)
=======
                      backgroundColor: context.surfaceSoft,
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? Icon(Icons.person, size: 16, color: context.textMuted)
>>>>>>> Stashed changes
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.post.authorUsername,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.post.caption,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                ),
<<<<<<< Updated upstream
=======
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _translateCaption(context),
                  icon: const Icon(Icons.translate, size: 18),
                  label: const Text('Translate'),
                ),
>>>>>>> Stashed changes
              ],
            ),
          ),
        );
      },
    );
  }

<<<<<<< Updated upstream
=======
  Future<void> _translateCaption(BuildContext context) async {
    final raw = widget.post.caption.trim();
    if (raw.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PostTranslateSheet(text: raw),
    );
  }

>>>>>>> Stashed changes
  void _openShareSheet(BuildContext context, WidgetRef ref) {
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref2, _) {
            final inboxAsync = ref2.watch(inboxProvider);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.65,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Send to',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: inboxAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                        data: (convs) {
                          if (convs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No conversations yet.\nStart a chat first.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: convs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = convs[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: c.otherAvatarUrl.isNotEmpty
                                      ? NetworkImage(c.otherAvatarUrl)
                                      : null,
                                  child: c.otherAvatarUrl.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                title: Text(c.otherUsername),
                                subtitle: Text(
                                  c.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.send,
                                    color: Color(0xFFB05ECC)),
                                onTap: () async {
                                  await _shareAs(
                                      ref2, c.chatId, currentUid, c.otherUid);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Shared to ${c.otherUsername}'),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareAs(
    WidgetRef ref,
    String chatId,
    String senderUid,
    String receiverUid,
  ) async {
    await ref.read(chatServiceProvider).sendMessage(
          chatId: chatId,
          senderUid: senderUid,
          receiverUid: receiverUid,
          text: '',
          sharedPostId: widget.post.id,
        );
  }

  Widget _miniIcon(String svgPath, String text) {
    return Row(
      children: [
        SvgPicture.asset(
          svgPath,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const SizedBox(width: 20, height: 20),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}

class _OwnerMenu extends StatelessWidget {
  final Post post;
  final WidgetRef ref;

  const _OwnerMenu({required this.post, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
        padding: EdgeInsets.zero,
        onSelected: (action) async {
          if (action == 'edit') {
            await _edit(context);
          } else if (action == 'visibility') {
            await _toggleVisibility(context);
          } else if (action == 'delete') {
            await _delete(context);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Edit caption'),
            ]),
          ),
          PopupMenuItem(
            value: 'visibility',
            child: Row(children: [
              Icon(post.isPrivate ? Icons.public : Icons.lock_outline,
                  size: 18),
              const SizedBox(width: 8),
              Text(post.isPrivate ? 'Make public' : 'Make followers-only'),
            ]),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final ctrl = TextEditingController(text: post.caption);
    final newCaption = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit caption'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Caption',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newCaption != null && newCaption != post.caption) {
      try {
        await ref.read(postServiceProvider).updatePost(
              post.id,
              caption: newCaption,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  Future<void> _toggleVisibility(BuildContext context) async {
    try {
      await ref.read(postServiceProvider).updatePost(
            post.id,
            isPrivate: !post.isPrivate,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(postServiceProvider).deletePost(post.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int activeIndex;

  const _PageDots({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (i) {
          final isActive = i == activeIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.symmetric(horizontal: i == 0 ? 0 : 3),
            width: isActive ? 7 : 5,
            height: isActive ? 7 : 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  isActive ? Colors.white : Colors.white.withValues(alpha: 0.5),
            ),
          );
        }),
      ),
    );
  }
}
<<<<<<< Updated upstream
=======

/// Inline-expandable caption. Shows up to [collapsedMaxLines] then truncates
/// with a "Read more" / "Show less" toggle. Used for text-only post hero
/// captions where a full bottom-sheet would feel too heavy. Only renders the
/// toggle when the text actually overflows the collapsed height.
class _ExpandableCaption extends StatefulWidget {
  final String text;
  final int collapsedMaxLines;
  final TextStyle style;
  final Color toggleColor;
  final TextAlign textAlign;

  const _ExpandableCaption({
    required this.text,
    required this.style,
    this.collapsedMaxLines = 6,
    this.toggleColor = const Color(0xFFB05ECC),
    this.textAlign = TextAlign.start,
  });

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure how the text would lay out if it were unconstrained on
        // line count. If didExceedMaxLines is false the text fits — show
        // it as-is with no toggle. Otherwise show the truncated/expanded
        // form plus the toggle.
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.collapsedMaxLines,
          textAlign: widget.textAlign,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        if (!tp.didExceedMaxLines) {
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.textAlign == TextAlign.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: _expanded ? null : widget.collapsedMaxLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: TextStyle(
                  color: widget.toggleColor,
                  fontSize: (widget.style.fontSize ?? 14) - 2,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet for translating a post caption. Mirrors the comment translate
/// sheet: a horizontal chip strip lets the user pick a target language and
/// the result is re-fetched on each selection (cache makes repeats instant).
class _PostTranslateSheet extends StatefulWidget {
  final String text;
  const _PostTranslateSheet({required this.text});

  @override
  State<_PostTranslateSheet> createState() => _PostTranslateSheetState();
}

class _PostTranslateSheetState extends State<_PostTranslateSheet> {
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
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
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
>>>>>>> Stashed changes
