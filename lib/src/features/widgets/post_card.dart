import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../providers/story_providers.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../../utils/media_cache.dart';
import '../model/post_model.dart';
import '../screens/comment_screen.dart';
import '../screens/create_discuss_screen.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/qa_thread_screen.dart';
import '../../navigation/user_profile_nav.dart';
import 'mention_text.dart';

class PostCard extends ConsumerStatefulWidget {
  final Post post;

  const PostCard({
    super.key,
    required this.post,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with SingleTickerProviderStateMixin {
  // Optimistic UI: non-null while a like toggle is in-flight.
  bool? _pendingLike;
  // null = follow the default (raised for all post types so the caption is
  // visible). Once the user taps the chevron we honor their choice via this
  // override — they can lower it on video posts to see the video unobstructed.
  bool? _captionBoxLoweredOverride;

  bool get _captionBoxLowered => _captionBoxLoweredOverride ?? false;

  /// Measured height of the caption / action panel — fed to the video
  /// player so it can position its scrubber bar above the panel
  /// instead of letting them collide. The key is attached to the
  /// panel's outermost positioned box; a post-frame callback reads
  /// `RenderBox.size.height` and stores it here.
  final GlobalKey _captionPanelKey = GlobalKey();
  double _captionPanelHeight = 0;

  void _measureCaptionPanel() {
    final ctx = _captionPanelKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if ((h - _captionPanelHeight).abs() < 0.5) return;
    setState(() => _captionPanelHeight = h);
  }

  // Carousel state for multi-image posts.
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Outer carousel: page 0 is Discuss threads (swipe right to reach it),
  // page 1 (the default) is the post itself.
  final PageController _discussPageController =
      PageController(initialPage: 1);

  // Double-tap-to-like heart burst animation. Driven once per double tap;
  // a value of 0 means the overlay is hidden.
  late final AnimationController _heartBurst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _pageController.dispose();
    _discussPageController.dispose();
    _heartBurst.dispose();
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

  /// Double-tap on the media area always *likes* (never unlikes) and plays
  /// a heart-burst animation so the user gets clear feedback. If the post is
  /// already liked we still play the animation as a confirmation but don't
  /// flip the state — Instagram-style.
  Future<void> _likeFromDoubleTap() async {
    HapticFeedback.lightImpact();
    _heartBurst.forward(from: 0);
    final currentLiked =
        ref.read(isLikedProvider(widget.post.id)).value ?? false;
    if (currentLiked || _pendingLike != null) return;
    setState(() => _pendingLike = true);
    try {
      await ref.read(postServiceProvider).toggleLike(widget.post.id);
    } finally {
      if (mounted) setState(() => _pendingLike = null);
    }
  }

  Future<void> _toggleSave() async {
    final wasSaved = ref.read(isSavedProvider(widget.post.id)).value ?? false;
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    try {
      await ref.read(postServiceProvider).toggleSave(widget.post.id);
      AppFeedback.showSuccessOn(
        messenger,
        wasSaved ? t.postCardRemovedFromSaved : t.postCardSavedToProfile,
      );
    } catch (e) {
      AppFeedback.showErrorOn(messenger, t.postCardCouldNotSave(e));
    }
  }

  Future<void> _toggleRepost() async {
    final wasReposted =
        ref.read(isRepostedProvider(widget.post.id)).value ?? false;
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    try {
      await ref.read(postServiceProvider).toggleRepost(widget.post.id);
      ref.invalidate(repostsCountProvider(widget.post.id));
      ref.invalidate(repostUserIdsProvider(widget.post.id));
      ref.invalidate(isRepostedProvider(widget.post.id));
      AppFeedback.showSuccessOn(
        messenger,
        wasReposted ? t.postCardRepostRemoved : t.postCardRepostedToProfile,
      );
    } catch (e) {
      AppFeedback.showErrorOn(messenger, t.postCardCouldNotRepost(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final userData = ref.watch(userByUidProvider(post.authorUid)).value;
    final avatarUrl = (userData?['avatarUrl'] as String?) ?? post.authorAvatar;
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
    final captionPreview = hasCaption ? post.caption.trim() : '';
    final postTime = context.t.timeAgo(post.createdAt);
    // Measure the caption panel after the frame so the video player
    // can position its scrubber above it on the next paint. The
    // measure is cheap (single RenderBox read) and short-circuits
    // when the height hasn't changed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCaptionPanel());

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
          // Page 0 is the Discuss threads made about this post (swipe
          // right from the post to reach it); page 1 is the post itself,
          // unchanged below.
          child: PageView(
            controller: _discussPageController,
            physics: const ClampingScrollPhysics(),
            children: [
              _PostDiscussPage(post: post),
              Stack(
                children: [
                  Positioned.fill(
                child: hasVideo
                    ? GestureDetector(
                        // Double-tap to like, layered on top of the video so
                        // single taps (play/pause / show-controls) still reach
                        // the player below.
                        behavior: HitTestBehavior.deferToChild,
                        onDoubleTap: _likeFromDoubleTap,
                        child: _PostVideoPlayer(
                          url: post.videoUrls.first,
                          captionPanelLowered: _captionBoxLowered,
                          captionPanelHeight: _captionPanelHeight,
                        ),
                      )
                    : hasImage
                        ? (isMulti
                            ? PageView.builder(
                                controller: _pageController,
                                itemCount: imageCount,
                                onPageChanged: (i) =>
                                    setState(() => _currentPage = i),
                                itemBuilder: (_, i) => GestureDetector(
                                  onDoubleTap: _likeFromDoubleTap,
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
                                    cacheManager: kIsWeb ? null : MediaCache.images,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: context.borderColor,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: context.borderColor,
                                      child: Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          color: context.textSecondary,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onDoubleTap: _likeFromDoubleTap,
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
                                  cacheManager: kIsWeb ? null : MediaCache.images,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: context.borderColor,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: context.borderColor,
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image_rounded,
                                        color: context.textSecondary,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              ))
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _likeFromDoubleTap,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF4A3A68),
                                    Color(0xFF1F1D30),
                                  ],
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
              // Double-tap-to-like heart burst. Pops in, holds, then fades
              // out — sized to the card so it reads as the primary feedback.
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _heartBurst,
                      builder: (context, _) {
                        final v = _heartBurst.value;
                        if (v == 0) return const SizedBox.shrink();
                        // 0..0.35 pop in, 0.35..0.65 hold, 0.65..1 fade out.
                        final scale = v < 0.35
                            ? Curves.easeOutBack.transform(v / 0.35) * 1.0
                            : v < 0.65
                                ? 1.0
                                : 1.0 - 0.1 * ((v - 0.65) / 0.35);
                        final opacity = v < 0.35
                            ? (v / 0.35).clamp(0.0, 1.0)
                            : v < 0.65
                                ? 1.0
                                : (1.0 - (v - 0.65) / 0.35).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 130,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 24,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 12,
                start: 14,
                end: 56,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: (post.authorUid == 'wikimedia_foundation' ||
                            post.authorUid == 'nasa_apod')
                        ? null
                        : () => openUserProfile(context, uid: post.authorUid),
                    child: _frostedChip(
                      avatarUrl: avatarUrl,
                      title: context.t.isolate(username),
                      subtitle: postTime,
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
              ),
              if (isOwner)
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: _OwnerMenu(post: post, ref: ref),
                )
              else
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: _ViewerMenu(post: post, ref: ref),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  key: _captionPanelKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_captionBoxLowered) ...[
                      if (repostsEnabled && currentUid != null)
                        _RepostBubbleCluster(
                          postId: post.id,
                          viewerUid: currentUid,
                        ),
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
                                        child: MentionText(
                                          text: captionPreview,
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
                                          child: PoppingActionIcon(
                                            active: isLiked,
                                            activeIcon: Icons.favorite,
                                            inactiveIcon: Icons.favorite_border,
                                            activeColor: AppColors.purple,
                                            inactiveColor: Colors.white,
                                            size: 20,
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
                                          child: const PoppingActionIcon(
                                            active: false,
                                            activeIcon:
                                                Icons.mode_comment_outlined,
                                            inactiveIcon:
                                                Icons.mode_comment_outlined,
                                            activeColor: Colors.white,
                                            inactiveColor: Colors.white,
                                            size: 20,
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
                                          child: const PoppingActionIcon(
                                            active: false,
                                            activeIcon: Icons.send_outlined,
                                            inactiveIcon: Icons.send_outlined,
                                            activeColor: Colors.white,
                                            inactiveColor: Colors.white,
                                            size: 20,
                                          ),
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
                                            _captionBoxLoweredOverride =
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
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                  ],
                ),
              ),
              if (_captionBoxLowered)
                PositionedDirectional(
                  end: 20,
                  bottom: 14,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _captionBoxLoweredOverride = false),
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
    required String title,
    String? subtitle,
    bool compact = false,
    TextDirection? textDirection,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 14 : 20),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 10 : 14,
          sigmaY: compact ? 10 : 14,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 4 : (subtitle != null ? 5 : 7),
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(compact ? 14 : 20),
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
            textDirection: textDirection,
            children: [
              if (avatarUrl != null)
                CircleAvatar(
                  radius: compact ? 8 : (subtitle != null ? 14 : 12),
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
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textDirection: textDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1.5),
                      Text(
                        subtitle,
                        textDirection: textDirection,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: compact ? 9.5 : 10.5,
                          fontWeight: FontWeight.w400,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
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
                // Hide Translate when the caption has no translatable text
                // (emoji-only / symbols-only). Translation APIs return the
                // emoji unchanged anyway, so the button would be a no-op.
                if (!_isEmojiOnlyCaption(widget.post.caption))
                  TextButton.icon(
                    onPressed: () => _translateCaption(context),
                    icon: const Icon(Icons.translate, size: 18),
                    label: Text(context.t.translate),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _translateCaption(BuildContext context) async {
    // Strip emojis before translation — the API returns them unchanged but
    // bundling them with the text occasionally trips language detection on
    // captions that are mostly emoji with a few words. Empty result means
    // the caption was emoji-only and there's nothing to translate.
    final stripped = _stripEmoji(widget.post.caption).trim();
    if (stripped.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PostTranslateSheet(
        text: stripped,
        target: ref.read(preferredLanguageProvider),
      ),
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
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.t.postCardSendTo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Share the post to the current user's story.
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.add,
                            color: Colors.white, size: 22),
                      ),
                      title: Text(context.t.postCardAddToStory),
                      subtitle: Text(
                        context.t.postCardAddToStorySub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        await _shareToStory(ref2);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    Expanded(
                      child: inboxAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) =>
                            Center(child: Text(context.t.homeErrorPrefix(e))),
                        data: (convs) {
                          if (convs.isEmpty) {
                            return Center(
                              child: Text(
                                context.t.postCardNoConversations,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                            itemCount: convs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c = convs[i];
                              return _ShareRecipientCard(
                                avatarUrl: c.otherAvatarUrl,
                                title: c.otherUsername,
                                onSend: () async {
                                  await _shareAs(
                                      ref2, c.chatId, currentUid, c.otherUid);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(context.t
                                            .postCardSharedTo(c.otherUsername)),
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

  /// Adds the post to the current user's story as a "shared post"
  /// story. The story carries `sharedPostId` so the viewer renders it
  /// as a tappable card; the post's first image (if any) is used as
  /// the story image so it still has a thumbnail.
  Future<void> _shareToStory(WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.t;
    try {
      final storyImage =
          widget.post.imageUrls.isNotEmpty ? widget.post.imageUrls.first : '';
      await ref.read(storyServiceProvider).createStory(
            imageUrl: storyImage,
            sharedPostId: widget.post.id,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(strings.postCardAddedToStory)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.postCardStoryFailed(e))),
      );
    }
  }

}

/// The Discuss page of a post's swipe carousel (page 2, reached by
/// swiping left on the card). Shows every discussion thread made about
/// this specific post, or an invite to start the first one.
class _PostDiscussPage extends ConsumerWidget {
  final Post post;
  const _PostDiscussPage({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(postDiscussionsProvider(post.id));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1A1A1E) : Colors.white,
      ),
      child: threadsAsync.when(
        data: (threads) {
          if (threads.isEmpty) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => discussPost(context, ref, post),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined,
                        size: 40, color: context.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      context.t.postCardNoDiscussBeFirst,
                      style: TextStyle(
                        color: context.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: threads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _DiscussPreviewRow(thread: threads[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            context.t.errorGeneric,
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// One discussion thread in [_PostDiscussPage]'s list — author, question
/// preview, and reply count. Tapping opens the full thread.
class _DiscussPreviewRow extends StatelessWidget {
  final Post thread;
  const _DiscussPreviewRow({required this.thread});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QaThreadScreen(post: thread)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: context.purpleSoft,
                backgroundImage: (thread.authorAvatar != null &&
                        thread.authorAvatar!.isNotEmpty)
                    ? CachedNetworkImageProvider(thread.authorAvatar!)
                    : null,
                child: (thread.authorAvatar == null ||
                        thread.authorAvatar!.isEmpty)
                    ? Icon(Icons.person, size: 16, color: context.textSecondary)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          context.t.timeAgo(thread.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: context.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      thread.caption.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.mode_comment_outlined,
                            size: 14, color: context.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${thread.commentsCount < 0 ? 0 : thread.commentsCount}',
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepostBubbleCluster extends ConsumerWidget {
  final String postId;
  final String viewerUid;

  const _RepostBubbleCluster({
    required this.postId,
    required this.viewerUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repostUids =
        ref.watch(repostUserIdsProvider(postId)).valueOrNull ?? const [];
    final following =
        ref.watch(followingProvider(viewerUid)).valueOrNull ?? const [];
    final followingSet = following.toSet();
    final visibleUids =
        repostUids.where((uid) => followingSet.contains(uid)).toList();

    if (visibleUids.isEmpty) return const SizedBox.shrink();

    final shown = visibleUids.take(2).toList();
    final hasOverflow = visibleUids.length > 2;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, bottom: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: hasOverflow ? 132 : (shown.length == 1 ? 48 : 84),
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < shown.length; i++)
                PositionedDirectional(
                  start: i == 0 ? 0 : 34,
                  top: i == 0 ? 10 : 0,
                  child: _RepostBubble(uid: shown[i]),
                ),
              if (hasOverflow)
                PositionedDirectional(
                  start: 78,
                  top: 12,
                  child: _RepostMoreButton(
                    uids: visibleUids,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepostBubble extends ConsumerWidget {
  final String uid;

  const _RepostBubble({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByUidProvider(uid)).valueOrNull;
    final avatar = (user?['avatarUrl'] as String?) ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(context, uid: uid),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.72),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          backgroundImage:
              avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
          child: avatar.isEmpty
              ? const Icon(Icons.person, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _RepostMoreButton extends StatelessWidget {
  final List<String> uids;

  const _RepostMoreButton({required this.uids});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showRepostUsers(context, uids),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.34),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  void _showRepostUsers(BuildContext context, List<String> uids) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _RepostUsersSheet(uids: uids),
    );
  }
}

class _RepostUsersSheet extends StatelessWidget {
  final List<String> uids;

  const _RepostUsersSheet({required this.uids});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.t.postCardRepostedBy,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  18 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: uids.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _RepostUserRow(uid: uids[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepostUserRow extends ConsumerWidget {
  final String uid;

  const _RepostUserRow({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByUidProvider(uid)).valueOrNull;
    final username = (user?['username'] as String?) ?? '';
    final avatar = (user?['avatarUrl'] as String?) ?? '';

    return ListTile(
      onTap: () => openUserProfile(context, uid: uid),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: context.inputFill,
        backgroundImage:
            avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
        child: avatar.isEmpty
            ? Icon(Icons.person, color: context.textSecondary)
            : null,
      ),
      title: Text(
        username.isEmpty ? uid : username,
        style: TextStyle(
          color: context.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textSecondary),
    );
  }
}

class _PostVideoPlayer extends StatefulWidget {
  final String url;
  // When the caption/action panel is raised, the inline control bar slides
  // up to clear it. When the panel is lowered, the controls sit near the
  // bottom edge of the card.
  final bool captionPanelLowered;
  // Measured height of the caption / action panel that sits at the
  // bottom of the post card. The scrubber bar is positioned at
  // `captionPanelHeight + a small gap` from the bottom so longer
  // captions (2 lines) no longer push the panel over the controls.
  // The post card writes this on every paint via a GlobalKey.
  final double captionPanelHeight;
  const _PostVideoPlayer({
    required this.url,
    required this.captionPanelLowered,
    required this.captionPanelHeight,
  });

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<_PostVideoPlayer> {
  VideoPlayerController? _controller;
  bool _muted = true;
  bool _showControls = true;
  bool _scrubbing = false;
  // True when the user explicitly paused via the controls — we don't want
  // visibility-based resume to override an intentional pause.
  bool _userPaused = false;
  Duration _scrubPosition = Duration.zero;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _setupController(widget.url);
  }

  /// Builds the controller for [url]. The video is first downloaded to
  /// the disk cache (so it never re-streams from the server), then
  /// played from that local file.
  Future<void> _setupController(String rawUrl) async {
    final url = normalizeMediaUrl(rawUrl);
    if (url.isEmpty) return;
    VideoPlayerController controller;
    if (kIsWeb) {
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
    } else {
      try {
        final file = await MediaCache.videoFile(url);
        if (!mounted) return;
        controller = VideoPlayerController.file(file);
      } catch (_) {
        // Cache miss/failure — fall back to streaming the network URL.
        if (!mounted) return;
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
    }

    // The widget may have been swapped to another post while the
    // cache download was in flight — bail if so.
    if (!mounted || rawUrl != widget.url) {
      controller.dispose();
      return;
    }

    _controller = controller
      ..setLooping(true)
      ..setVolume(_muted ? 0 : 1)
      ..addListener(_onTick);
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {});
    controller.play();
    _scheduleHide();
  }

  void _onTick() {
    if (!mounted) return;
    // Cheap rebuild so the seek bar / time labels track playback. setState
    // here is fine — the controller fires roughly once per frame while
    // playing and not at all when paused.
    if (!_scrubbing) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PostVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the list re-uses this State for a different post (e.g. a new post
    // is prepended and the existing element slots into a new index), swap
    // controllers so we don't keep showing the old video.
    if (oldWidget.url != widget.url) {
      final old = _controller;
      old?.removeListener(_onTick);
      old?.dispose();
      _controller = null;
      _hideTimer?.cancel();
      _showControls = true;
      _scrubbing = false;
      _scrubPosition = Duration.zero;
      _setupController(widget.url);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && (_controller?.value.isPlaying ?? false) && !_scrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsThenAutoHide() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _userPaused = true;
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        c.play();
        _userPaused = false;
        _showControlsThenAutoHide();
      }
    });
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;
    // Pause once more than half the card leaves the viewport; resume only
    // when at least half is back in view AND the user hadn't tapped pause.
    if (info.visibleFraction < 0.5) {
      if (c.value.isPlaying) c.pause();
    } else {
      if (!_userPaused && !c.value.isPlaying) {
        c.play();
      }
    }
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller?.setVolume(_muted ? 0 : 1);
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
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final isPlaying = ready && c.value.isPlaying;
    final duration = ready ? c.value.duration : Duration.zero;
    final position = _scrubbing
        ? _scrubPosition
        : (ready ? c.value.position : Duration.zero);
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
    return VisibilityDetector(
      key: ValueKey('postvid:${widget.url}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
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
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
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
            // Bottom control bar (scrub + times). Positioned just above
            // the measured caption / action panel so multi-line captions
            // can't push the panel over the scrubber. When the user
            // lowers the panel (chevron tap), it shifts off-screen and
            // the scrubber drops near the bottom edge.
            if (ready)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: 12,
                right: 12,
                bottom: widget.captionPanelLowered
                    // Lowered: panel is hidden, scrubber sits near the
                    // bottom edge with just enough room for a finger.
                    ? 48
                    // Raised: clear the panel + 12 px gap + the panel's
                    // own 12 px bottom offset. Falls back to 105 (the
                    // old static value) before the post-frame measure
                    // has populated the height.
                    : (widget.captionPanelHeight > 0
                        ? widget.captionPanelHeight + 24
                        : 105),
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
                                    value:
                                        posMs.clamp(0, maxMs <= 0 ? 1 : maxMs),
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
                                      await _controller?.seekTo(
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
                              const SizedBox(width: 2),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _openFullscreen,
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: 20,
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
      ),
    );
  }

  Future<void> _openFullscreen() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final wasPlaying = c.value.isPlaying;
    final startAt = c.value.position;
    c.pause();
    _hideTimer?.cancel();

    final result = await Navigator.of(context).push<_FullscreenResult>(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullscreenVideoScreen(
          url: widget.url,
          startAt: startAt,
          muted: _muted,
          autoPlay: wasPlaying,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _controller?.seekTo(result.position);
      if (result.muted != _muted) {
        setState(() {
          _muted = result.muted;
          _controller?.setVolume(_muted ? 0 : 1);
        });
      }
      if (result.wasPlaying) {
        _controller?.play();
      }
    } else if (wasPlaying) {
      _controller?.play();
    }
    _showControlsThenAutoHide();
  }
}

class _FullscreenResult {
  final Duration position;
  final bool wasPlaying;
  final bool muted;
  const _FullscreenResult({
    required this.position,
    required this.wasPlaying,
    required this.muted,
  });
}

class _FullscreenVideoScreen extends StatefulWidget {
  final String url;
  final Duration startAt;
  final bool muted;
  final bool autoPlay;
  const _FullscreenVideoScreen({
    required this.url,
    required this.startAt,
    required this.muted,
    required this.autoPlay,
  });

  @override
  State<_FullscreenVideoScreen> createState() => _FullscreenVideoScreenState();
}

class _FullscreenVideoScreenState extends State<_FullscreenVideoScreen> {
  late VideoPlayerController _controller;
  bool _muted = true;
  bool _showControls = true;
  bool _scrubbing = false;
  bool _isLandscape = false;
  Duration _scrubPosition = Duration.zero;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final cleanUrl = normalizeMediaUrl(widget.url);
    _controller = VideoPlayerController.networkUrl(Uri.parse(cleanUrl))
      ..setLooping(true)
      ..setVolume(_muted ? 0 : 1)
      ..addListener(_onTick)
      ..initialize().then((_) async {
        if (!mounted) return;
        if (widget.startAt > Duration.zero) {
          await _controller.seekTo(widget.startAt);
        }
        if (widget.autoPlay) _controller.play();
        setState(() {});
        _scheduleHide();
      });
  }

  void _onTick() {
    if (!mounted) return;
    if (!_scrubbing) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    // Restore orientations + system UI for the rest of the app.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
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

  Future<void> _toggleLandscape() async {
    if (_isLandscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (!mounted) return;
    setState(() => _isLandscape = !_isLandscape);
    _showControlsThenAutoHide();
  }

  void _exit() {
    Navigator.of(context).pop(_FullscreenResult(
      position: _controller.value.isInitialized
          ? _controller.value.position
          : Duration.zero,
      wasPlaying: _controller.value.isPlaying,
      muted: _muted,
    ));
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
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
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  ),
                ),
              // Top bar: close + landscape toggle
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _showControls ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Row(
                      children: [
                        _circleButton(
                          icon: Icons.close,
                          onTap: _exit,
                        ),
                        const Spacer(),
                        _circleButton(
                          icon: _isLandscape
                              ? Icons.screen_lock_portrait
                              : Icons.screen_rotation,
                          onTap: _toggleLandscape,
                          tooltip: _isLandscape
                              ? context.t.postCardSwitchPortrait
                              : context.t.postCardSwitchLandscape,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Center play/pause
              if (ready && _showControls)
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _togglePlay,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              // Bottom control bar
              if (ready)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _showControls ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(24),
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
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _fmt(position),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor:
                                          Colors.white.withValues(alpha: 0.3),
                                      thumbColor: Colors.white,
                                      overlayColor:
                                          Colors.white.withValues(alpha: 0.15),
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 7),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 16),
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: maxMs <= 0 ? 1 : maxMs,
                                      value: posMs.clamp(
                                          0, maxMs <= 0 ? 1 : maxMs),
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
                                    fontSize: 12,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleMute,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      _muted
                                          ? Icons.volume_off
                                          : Icons.volume_up,
                                      color: Colors.white,
                                      size: 22,
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
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}

/// Turns [post] into a Discuss (Q&A) topic — or opens the existing
/// one — and navigates to its thread. Shared by the owner and viewer
/// post menus.
///
/// If the post already has a Discuss thread it just opens it. For a
/// new topic it first asks the user to type their question about the
/// post, then creates the topic (question + linked post) and opens it.
/// Starts a NEW discussion about [post] and opens its thread. Every user can
/// create their own discussion of the same post — we always ask for the
/// question and always create a fresh topic (no reuse/dedupe). To browse
/// discussions others already made about this post, swipe left on its card.
Future<void> discussPost(
  BuildContext context,
  WidgetRef ref,
  Post post,
) async {
  // Open the same full-screen create-discuss interface used by the Discuss
  // tab, pre-linked to this post. The screen handles creating the thread
  // (question + optional details) and navigating to it on submit, so this
  // is just a push.
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CreateDiscussScreen(sourcePost: post)),
  );
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
          } else if (action == 'discuss') {
            await discussPost(context, ref, post);
          } else if (action == 'delete') {
            await _delete(context);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(context.t.postCardEditCaption),
            ]),
          ),
          PopupMenuItem(
            value: 'visibility',
            child: Row(children: [
              Icon(post.isPrivate ? Icons.public : Icons.lock_outline,
                  size: 18),
              const SizedBox(width: 8),
              Text(post.isPrivate
                  ? context.t.postCardMakePublic
                  : context.t.postCardMakeFollowersOnly),
            ]),
          ),
          // Always available: start your OWN discussion of this post.
          // (Discussions others made about it are reachable by swiping
          // left on the card itself.)
          PopupMenuItem(
            value: 'discuss',
            child: Row(children: [
              const Icon(Icons.forum_outlined, size: 18),
              const SizedBox(width: 8),
              Text(context.t.postCardDiscussThisPost),
            ]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text(context.t.delete, style: const TextStyle(color: Colors.red)),
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
        title: Text(context.t.postCardEditCaption),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: context.t.postCardCaptionHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(context.t.save)),
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.postCardFailed(e))));
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
            .showSnackBar(SnackBar(content: Text(context.t.postCardFailed(e))));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.postCardDeletePostTitle),
        content: Text(context.t.postCardCannotBeUndone),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.delete,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(postServiceProvider).deletePost(post.id);
        ref.invalidate(feedProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.postCardFailed(e))));
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
          } else if (action == 'discuss') {
            await discussPost(context, ref, post);
          }
        },
        itemBuilder: (_) => [
          // Always available: start your OWN discussion of this post.
          // (Discussions others made about it are reachable by swiping
          // left on the card itself.)
          PopupMenuItem(
            value: 'discuss',
            child: Row(children: [
              const Icon(Icons.forum_outlined, size: 18),
              const SizedBox(width: 8),
              Text(context.t.postCardDiscussThisPost),
            ]),
          ),
          PopupMenuItem(
            value: 'report',
            child: Row(children: [
              const Icon(Icons.flag_outlined, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text(context.t.report, style: const TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    final detailsCtrl = TextEditingController();
    var selectedReason = _reportReasons.first;
    final reportSentMsg = context.t.postCardReportSentAdmins;

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
                                context.t.postCardReportPost,
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
                          context.t.postCardPickReasonPost,
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
                              context.t.reportReasonLabel(reason),
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

      final messenger = ScaffoldMessenger.of(context);
      await ref.read(postServiceProvider).reportPost(
            post: post,
            reason: selectedReason,
            details: detailsCtrl.text,
          );
      if (context.mounted) {
        AppFeedback.showInfoOn(messenger, reportSentMsg);
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
          return MentionText(
            text: widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            mentionStyle: widget.style.copyWith(
              color: widget.toggleColor,
              fontWeight: FontWeight.w700,
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.textAlign == TextAlign.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            MentionText(
              text: widget.text,
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: _expanded ? null : widget.collapsedMaxLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              mentionStyle: widget.style.copyWith(
                color: widget.toggleColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? context.t.postCardShowLess
                    : context.t.postCardReadMore,
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

// Unicode ranges covering the bulk of emoji/pictograph characters plus
// the variation-selector and zero-width joiner used inside multi-codepoint
// emoji sequences. Stripping these leaves the actual text behind so the
// translator only sees real words.
final RegExp _emojiPattern = RegExp(
  r'[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{1FA70}-\u{1FAFF}'
  r'\u{1F1E6}-\u{1F1FF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}'
  r'\u{2B00}-\u{2BFF}\u{1F100}-\u{1F1FF}\u{FE00}-\u{FE0F}\u{200D}]+',
  unicode: true,
);

String _stripEmoji(String s) => s.replaceAll(_emojiPattern, '');

bool _isEmojiOnlyCaption(String s) => _stripEmoji(s).trim().isEmpty;

/// Bottom sheet for translating a post caption. Mirrors the comment
/// translate sheet — horizontal chip strip lets the user pick a target
/// language, the result is re-fetched on each selection (cache makes
/// repeats instant).
class _PostTranslateSheet extends StatefulWidget {
  final String text;
  final String target;
  const _PostTranslateSheet({
    required this.text,
    required this.target,
  });

  @override
  State<_PostTranslateSheet> createState() => _PostTranslateSheetState();
}

class _PostTranslateSheetState extends State<_PostTranslateSheet> {
  late String _target;
  String? _translated;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
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
            SizedBox(
              height: 36,
              child: Builder(builder: (context) {
                // Dedupe by translation code — the speech-to-text list has
                // separate entries for English (USA) and (UK) but the
                // translation API treats them as one `en`, so showing both
                // chips made both light up simultaneously.
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
                              content: Text(context.t.commentTranslationCopied),
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

/// Single friend tile inside the post-share sheet. A rounded card with a
/// 26-radius avatar, the username, and a pill-shape Send CTA on the trailing
/// side. The whole card is tappable as well as the pill, so users can hit
/// either zone.
class _ShareRecipientCard extends StatelessWidget {
  final String avatarUrl;
  final String title;
  final VoidCallback onSend;

  const _ShareRecipientCard({
    required this.avatarUrl,
    required this.title,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onSend,
        child: Ink(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.borderColor.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: context.inputFill,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Icon(Icons.person, color: context.textSecondary)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFB05ECC).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t.postCardSend,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
