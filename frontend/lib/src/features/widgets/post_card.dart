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
                    child: Text(
                      post.caption,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: widget.post.authorAvatar != null
                          ? CachedNetworkImageProvider(
                              widget.post.authorAvatar!)
                          : null,
                      child: widget.post.authorAvatar == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.post.authorUsername,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  child: SelectableText(
                    widget.post.caption,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
