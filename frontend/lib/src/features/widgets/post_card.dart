import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../model/post_model.dart';
import '../screens/comment_screen.dart';
import '../screens/image_viewer_screen.dart';
import '../../navigation/user_profile_nav.dart';
import 'location_map.dart';

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final bool travelMode;
  final String? travelPlace;
  final String? travelDistance;

  /// When true the viewer's GPS location isn't available (services off or
  /// permission denied). The travel-mode card replaces the distance pill
  /// with a tappable "Turn on location" CTA so users know why distance
  /// is missing and can fix it in one tap.
  final bool viewerLocationOff;
  final VoidCallback? onTurnOnLocationTap;

  const PostCard({
    super.key,
    required this.post,
    this.travelMode = false,
    this.travelPlace,
    this.travelDistance,
    this.viewerLocationOff = false,
    this.onTurnOnLocationTap,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  // Optimistic UI: non-null while a like toggle is in-flight.
  bool? _pendingLike;
  bool _captionBoxLowered = false;

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

  Future<void> _toggleSave() async {
    final wasSaved = ref.read(isSavedProvider(widget.post.id)).value ?? false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(postServiceProvider).toggleSave(widget.post.id);
      AppFeedback.showSuccessOn(
        messenger,
        wasSaved ? 'Removed from saved' : 'Saved to your profile',
      );
    } catch (e) {
      AppFeedback.showErrorOn(messenger, 'Could not save post: $e');
    }
  }

  Future<void> _toggleRepost() async {
    final wasReposted =
        ref.read(isRepostedProvider(widget.post.id)).value ?? false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(postServiceProvider).toggleRepost(widget.post.id);
      AppFeedback.showSuccessOn(
        messenger,
        wasReposted ? 'Repost removed' : 'Reposted to your profile',
      );
    } catch (e) {
      AppFeedback.showErrorOn(messenger, 'Could not repost: $e');
    }
  }

  String _formatPostTimestamp(DateTime? dt) {
    if (dt == null) return 'just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final travelPlace = widget.travelPlace?.trim();
    final travelDistance = widget.travelDistance?.trim();
    final userData = ref.watch(userByUidProvider(post.authorUid)).value;
    final avatarUrl = userData?['avatarUrl'] as String?;
    final username = userData?['username'] as String? ?? post.authorUsername;
    final isLikedAsync = ref.watch(isLikedProvider(post.id));
    // Use optimistic value while in-flight, otherwise use live stream value.
    final isLiked = _pendingLike ?? isLikedAsync.value ?? false;
    final isRepostedAsync = ref.watch(isRepostedProvider(post.id));
    final isReposted = isRepostedAsync.value ?? false;
    final isSaved = ref.watch(isSavedProvider(post.id)).value ?? false;
    final repostsEnabled =
        ref.watch(adminConfigProvider).valueOrNull?.repostsEnabled ?? true;
    final hasVideo = post.videoUrls.isNotEmpty;
    final hasImage = post.imageUrls.isNotEmpty;
    final hasMedia = hasVideo || hasImage;
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final isOwner = currentUid != null && currentUid == post.authorUid;

    final imageCount = post.imageUrls.length;
    final isMulti = !hasVideo && imageCount > 1;
    final hasCaption = post.caption.trim().isNotEmpty;
    final hasTravelPlace =
        widget.travelMode && travelPlace != null && travelPlace.isNotEmpty;
    final captionPreview =
        hasCaption ? post.caption.trim() : (hasTravelPlace ? travelPlace : '');
    final postTime = _formatPostTimestamp(post.createdAt);

    final isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.1))
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: SizedBox(
          height: hasMedia ? 480 : 430,
          child: Stack(
            children: [
              Positioned.fill(
                child: hasVideo
                    ? _PostVideoPlayer(url: post.videoUrls.first)
                    : hasImage
                    ? (isMulti
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
                          ))
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF4A3A68), Color(0xFF1F1D30)],
                          ),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: _ExpandableCaption(
                              text: post.caption,
                              collapsedMaxLines: 4,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                              toggleColor: Colors.white,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.transparent,
                          Colors.black
                              .withValues(alpha: hasImage ? 0.62 : 0.44),
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openUserProfile(context, uid: post.authorUid),
                  child: _frostedChip(
                    avatarUrl: avatarUrl,
                    text: '$username • $postTime',
                  ),
                ),
              ),
              if (isOwner)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _OwnerMenu(post: post, ref: ref),
                )
              else
                Positioned(
                  top: 12,
                  right: 12,
                  child: _ViewerMenu(post: post, ref: ref),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset: _captionBoxLowered
                          ? const Offset(0, 0.72)
                          : Offset.zero,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isMulti) ...[
                            Center(
                              child: _frostedPanel(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: _PageDots(
                                    count: imageCount,
                                    activeIndex: _currentPage,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: _frostedPanel(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (captionPreview.isNotEmpty)
                                      GestureDetector(
                                        onTap: hasCaption
                                            ? () => _showFullCaption(
                                                context, avatarUrl, username)
                                            : null,
                                        child: Text(
                                          captionPreview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.92),
                                            fontSize: 14,
                                            height: 1.35,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    if (captionPreview.isNotEmpty)
                                      const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _toggleLike,
                                          child: Row(
                                            children: [
                                              Icon(
                                                isLiked
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
                                                color: isLiked
                                                    ? Colors.red
                                                    : Colors.white,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${post.likesCount}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: context.cardBg,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                top: Radius.circular(20),
                                              ),
                                            ),
                                            builder: (_) =>
                                                CommentScreen(post: post),
                                          ),
                                          child: _miniIcon(
                                            'assets/icons/Group.svg',
                                            '${post.commentsCount}',
                                          ),
                                        ),
                                        if (repostsEnabled) ...[
                                          const SizedBox(width: 14),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: _toggleRepost,
                                            child: PoppingActionIcon(
                                              active: isReposted,
                                              activeIcon: Icons.repeat,
                                              inactiveIcon: Icons.repeat,
                                              activeColor:
                                                  const Color(0xFFB05ECC),
                                              inactiveColor: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 14),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () =>
                                              _openShareSheet(context, ref),
                                          child: _miniIcon(
                                              'assets/icons/Send.svg', ''),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _toggleSave,
                                          child: PoppingActionIcon(
                                            active: isSaved,
                                            activeIcon: Icons.bookmark,
                                            inactiveIcon: Icons.bookmark_border,
                                            activeColor:
                                                const Color(0xFFB05ECC),
                                            inactiveColor: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => setState(() {
                                            _captionBoxLowered =
                                                !_captionBoxLowered;
                                          }),
                                          child: Container(
                                            width: 26,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white
                                                  .withValues(alpha: 0.18),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.28),
                                              ),
                                            ),
                                            child: Icon(
                                              _captionBoxLowered
                                                  ? Icons
                                                      .keyboard_arrow_up_rounded
                                                  : Icons
                                                      .keyboard_arrow_down_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasTravelPlace) ...[
                                      const SizedBox(height: 10),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          final lat = post.postLat;
                                          final lng = post.postLng;
                                          if (lat == null || lng == null) {
                                            return;
                                          }
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => LocationMapScreen(
                                                lat: lat,
                                                lng: lng,
                                                label: travelPlace,
                                                subtitle: post.postPlaceCity,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                travelPlace,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.92),
                                                  fontSize: 11,
                                                  decoration: post.postLat !=
                                                              null &&
                                                          post.postLng != null
                                                      ? TextDecoration.underline
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            if (widget.viewerLocationOff)
                                              GestureDetector(
                                                onTap:
                                                    widget.onTurnOnLocationTap,
                                                child: _frostedChip(
                                                  icon: Icons.location_off,
                                                  text: 'Turn on location',
                                                  compact: true,
                                                ),
                                              )
                                            else if (travelDistance != null &&
                                                travelDistance.isNotEmpty)
                                              _frostedChip(
                                                icon: Icons.route,
                                                text: travelDistance,
                                                compact: true,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_captionBoxLowered)
                Positioned(
                  right: 20,
                  bottom: 14,
                  child: GestureDetector(
                    onTap: () => setState(() => _captionBoxLowered = false),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.3),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frostedPanel({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _frostedChip({
    String? avatarUrl,
    IconData? icon,
    required String text,
    bool compact = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 14 : 22),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 10 : 14,
          sigmaY: compact ? 10 : 14,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(compact ? 14 : 22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: compact ? 0.2 : 0.3),
                blurRadius: compact ? 10 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatarUrl != null)
                CircleAvatar(
                  radius: compact ? 8 : 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  backgroundImage: CachedNetworkImageProvider(avatarUrl),
                )
              else
                Icon(
                  icon ?? Icons.person,
                  color: Colors.white,
                  size: compact ? 12 : 16,
                ),
              SizedBox(width: compact ? 5 : 8),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullCaption(
      BuildContext context, String? avatarUrl, String username) {
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
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      username,
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
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _translateCaption(context),
                  icon: const Icon(Icons.translate, size: 18),
                  label: const Text('Translate'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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

class _PostVideoPlayer extends StatefulWidget {
  final String url;
  const _PostVideoPlayer({required this.url});

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<_PostVideoPlayer> {
  late VideoPlayerController _controller;
  bool _muted = true;
  bool _showControls = true;
  bool _scrubbing = false;
  Duration _scrubPosition = Duration.zero;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..setVolume(0)
      ..addListener(_onTick)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
        _scheduleHide();
      });
  }

  void _onTick() {
    if (!mounted) return;
    // Cheap rebuild so the seek bar / time labels track playback. setState
    // here is fine — the controller fires roughly once per frame while
    // playing and not at all when paused.
    if (!_scrubbing) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && _controller.value.isPlaying && !_scrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsThenAutoHide() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        _controller.play();
        _showControlsThenAutoHide();
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller.setVolume(_muted ? 0 : 1);
    });
    _showControlsThenAutoHide();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.value.isInitialized;
    final isPlaying = ready && _controller.value.isPlaying;
    final duration = ready ? _controller.value.duration : Duration.zero;
    final position = _scrubbing
        ? _scrubPosition
        : (ready ? _controller.value.position : Duration.zero);
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_showControls) {
          _togglePlay();
        } else {
          _showControlsThenAutoHide();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
            ),
          // Center play/pause hint
          if (ready && _showControls)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showControls ? 1 : 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlay,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
          // Top-right mute toggle
          if (ready)
            Positioned(
              top: 12,
              right: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMute,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          // Bottom control bar (scrub + times). Sits above the post's own
          // action panel by being placed higher off the bottom edge.
          if (ready)
            Positioned(
              left: 12,
              right: 12,
              bottom: 130,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showControls ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _togglePlay,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _fmt(position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.5,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor:
                                      Colors.white.withValues(alpha: 0.3),
                                  thumbColor: Colors.white,
                                  overlayColor:
                                      Colors.white.withValues(alpha: 0.15),
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: maxMs <= 0 ? 1 : maxMs,
                                  value: posMs.clamp(0, maxMs <= 0 ? 1 : maxMs),
                                  onChangeStart: (_) {
                                    _scrubbing = true;
                                    _hideTimer?.cancel();
                                  },
                                  onChanged: (v) {
                                    setState(() {
                                      _scrubPosition =
                                          Duration(milliseconds: v.toInt());
                                    });
                                  },
                                  onChangeEnd: (v) async {
                                    await _controller.seekTo(
                                        Duration(milliseconds: v.toInt()));
                                    _scrubbing = false;
                                    _scheduleHide();
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _fmt(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleMute,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  _muted ? Icons.volume_off : Icons.volume_up,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
        ref.invalidate(feedProvider);
        ref.invalidate(travelFeedProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }
}

class _ViewerMenu extends StatelessWidget {
  final Post post;
  final WidgetRef ref;

  const _ViewerMenu({required this.post, required this.ref});

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
          if (action == 'report') {
            await _report(context);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'report',
            child: Row(children: [
              Icon(Icons.flag_outlined, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Report', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
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
                                'Report post',
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
                          'Pick the reason that best fits this post.',
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
                            hintText: 'Extra details (optional)',
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
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, true),
                                child: const Text('Send report'),
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

      final messenger = ScaffoldMessenger.of(context);
      await ref.read(postServiceProvider).reportPost(
            post: post,
            reason: selectedReason,
            details: detailsCtrl.text,
          );
      if (context.mounted) {
        AppFeedback.showInfoOn(messenger, 'Report sent to admins');
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.showErrorOn(ScaffoldMessenger.of(context), '$e');
      }
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => detailsCtrl.dispose());
    }
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int activeIndex;

  const _PageDots({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

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

/// Bottom sheet for translating a post caption. Mirrors the comment
/// translate sheet — horizontal chip strip lets the user pick a target
/// language, the result is re-fetched on each selection (cache makes
/// repeats instant).
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
                          Clipboard.setData(ClipboardData(text: _translated!));
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
