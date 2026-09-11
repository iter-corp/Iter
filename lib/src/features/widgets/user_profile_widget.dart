import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import 'profile_widget.dart' show ProfileDefaultCover, ProfileInitialAvatar;

/// COVER + AVATAR — uses live profile data
class UserCoverAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? coverUrl;
  final String? name;
  final bool isPrivate;
  final VoidCallback onBack;
  final bool showMenu;
  final VoidCallback? onBlockTap;
  final VoidCallback? onReportTap;
  final bool isBlocked;

  const UserCoverAvatar({
    super.key,
    required this.avatarUrl,
    required this.coverUrl,
    this.name,
    required this.isPrivate,
    required this.onBack,
    this.showMenu = false,
    this.onBlockTap,
    this.onReportTap,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final backArrow = Positioned(
      top: 40,
      left: 12,
      child: GestureDetector(
        onTap: onBack,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );

    final menuButton = showMenu
        ? Positioned(
            top: 40,
            right: 12,
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'block') {
                  onBlockTap?.call();
                } else if (value == 'report') {
                  onReportTap?.call();
                }
              },
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.more_vert, color: Colors.white, size: 20),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text(context.t.report,
                      style: const TextStyle(color: Colors.red)),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    isBlocked ? context.t.unblock : context.t.block,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final hasCover = coverUrl != null && coverUrl!.trim().isNotEmpty;

    final avatar = hasAvatar
        ? CachedNetworkImage(
            imageUrl: avatarUrl!,
            imageBuilder: (_, imageProvider) => CircleAvatar(
              radius: 40,
              backgroundColor: Colors.transparent,
              backgroundImage: imageProvider,
            ),
            placeholder: (_, __) =>
                ProfileInitialAvatar(name: name, radius: 40),
            errorWidget: (_, __, ___) =>
                ProfileInitialAvatar(name: name, radius: 40),
          )
        : ProfileInitialAvatar(name: name, radius: 40);

    if (isPrivate) {
      return SizedBox(
        height: 200,
        child: Stack(
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: hasCover
                    ? CachedNetworkImage(
                        imageUrl: coverUrl!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const ProfileDefaultCover(height: 140),
                        errorWidget: (_, __, ___) =>
                            const ProfileDefaultCover(height: 140),
                      )
                    : const ProfileDefaultCover(height: 140),
              ),
            ),
            Container(
              height: 140,
              color: Colors.black.withValues(alpha: 0.2),
            ),
            backArrow,
            menuButton,
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.cardBg,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: avatar,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: hasCover
                ? CachedNetworkImage(
                    imageUrl: coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const ProfileDefaultCover(height: 180),
                    errorWidget: (_, __, ___) =>
                        const ProfileDefaultCover(height: 180),
                  )
                : const ProfileDefaultCover(height: 180),
          ),
          backArrow,
          menuButton,
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.cardBg,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: avatar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// NAME + BIO
class UserNameBio extends StatelessWidget {
  final String username;
  final String handle;
  final String bio;
  final String profession;
  final String educationLevel;
  final String fieldOfStudy;
  final bool isPrivate;

  const UserNameBio({
    super.key,
    required this.username,
    required this.handle,
    this.bio = '',
    this.profession = '',
    this.educationLevel = '',
    this.fieldOfStudy = '',
    this.isPrivate = false,
  });
  @override
  Widget build(BuildContext context) {
    final prof = profession.trim();
    final edu = educationLevel.trim();
    final field = fieldOfStudy.trim();
    final badges = <Map<String, String>>[
      if (prof.isNotEmpty) {'label': prof, 'kind': 'profession'},
      if (edu.isNotEmpty) {'label': edu, 'kind': 'academic'},
      if (field.isNotEmpty) {'label': field, 'kind': 'field'},
    ];

    const nonPurpleFallbackPalette = <Color>[
      Color(0xFF2D6DD6), // navy-blue
      Color(0xFF1F8A45), // green
      Color(0xFFA95F14), // orange
      Color(0xFFC62828), // red
      Color(0xFFB7791F), // yellow-amber
      Color(0xFF00897B), // teal
    ];

    const academicColorMap = <String, Color>{
      'undergraduate': Color(0xFF7CB342),
      'masters': Color(0xFFA95F14),
      'phd': Color(0xFFC62828),
      'faculty': Color(0xFF00897B),
    };

    const fieldColorMap = <String, Color>{
      'tech': Color(0xFF2D6DD6),
      'medicine': Color(0xFF1F8A45),
      'law': Color(0xFF9A4A2B),
      'business': Color(0xFFB7791F),
      'arts': Color(0xFFC0567B),
      'engineering': Color(0xFF1E88E5),
      'science': Color(0xFF00897B),
      'education': Color(0xFF6D4C41),
      'social sciences': Color(0xFF7B5E57),
      'other': Color(0xFF5C6B73),
    };

    Color badgeColorFor({
      required String label,
      required String kind,
      required int idx,
    }) {
      if (kind == 'profession') return AppColors.purpleDeep;
      if (kind == 'academic') {
        return academicColorMap[label.toLowerCase()] ??
            nonPurpleFallbackPalette[idx % nonPurpleFallbackPalette.length];
      }
      if (kind == 'field') {
        return fieldColorMap[label.toLowerCase()] ??
            nonPurpleFallbackPalette[idx % nonPurpleFallbackPalette.length];
      }
      return nonPurpleFallbackPalette[idx % nonPurpleFallbackPalette.length];
    }

    return Padding(
      padding: const EdgeInsets.only(top: 52, bottom: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                username,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary),
              ),
              if (isPrivate) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.lock,
                  size: 18,
                  color: context.textSecondary,
                ),
              ],
            ],
          ),
          if (handle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              context.t.ltrHandle(handle),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ],
          if (bio.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              bio,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: badges.asMap().entries.map((entry) {
                final idx = entry.key;
                final label = entry.value['label']!;
                final kind = entry.value['kind']!;
                final fg = badgeColorFor(label: label, kind: kind, idx: idx);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: fg.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// STATS
class UserStats extends StatelessWidget {
  final int followers;
  final int following;
  final int posts;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final bool isPrivateAndNotFollowing;

  const UserStats({
    super.key,
    required this.followers,
    required this.following,
    required this.posts,
    this.onFollowersTap,
    this.onFollowingTap,
    this.isPrivateAndNotFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(
              context,
              isPrivateAndNotFollowing ? "—" : _fmt(followers),
              context.t.followers,
              isPrivateAndNotFollowing ? null : onFollowersTap),
          _divider(context),
          _statItem(
              context,
              isPrivateAndNotFollowing ? "—" : _fmt(following),
              context.t.following,
              isPrivateAndNotFollowing ? null : onFollowingTap),
          _divider(context),
          _statItem(context, isPrivateAndNotFollowing ? "—" : _fmt(posts),
              context.t.posts, null),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _statItem(
      BuildContext context, String value, String label, VoidCallback? onTap) {
    final content = Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: context.textSecondary)),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8), child: content);
  }

  Widget _divider(BuildContext context) =>
      Container(width: 1, height: 36, color: context.borderColor);
}

/// FOLLOW + MESSAGE BUTTONS
class UserButtons extends StatelessWidget {
  final bool isFollowing;
  final bool isRequested;
  final bool isPrivate;
  final VoidCallback onFollowTap;
  final VoidCallback? onMessageTap;

  const UserButtons({
    super.key,
    required this.isFollowing,
    this.isRequested = false,
    required this.isPrivate,
    required this.onFollowTap,
    this.onMessageTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isFollowing || isRequested;
    final String text = isFollowing
        ? context.t.following
        : (isRequested ? context.t.requested : context.t.follow);
    final IconData icon = isFollowing
        ? Icons.check
        : (isRequested ? Icons.access_time : Icons.person_add_alt_1_outlined);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          /// FOLLOW BUTTON — same OutlinedButton shape as ProfileButtons
          /// once following/requested; a filled purple CTA (matching the
          /// app's other primary actions) while not yet following.
          Expanded(
            child: active
                ? OutlinedButton.icon(
                    onPressed: onFollowTap,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.borderColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: Icon(icon, size: 16, color: context.textPrimary),
                    label: Text(text,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w600)),
                  )
                : ElevatedButton.icon(
                    onPressed: onFollowTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB05ECC),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined,
                        size: 16, color: Colors.white),
                    label: Text(text,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
          ),

          /// MESSAGE BUTTON — shown for public profiles, AND for
          /// private profiles once the follow has been accepted (so
          /// mutual followers can DM each other even when the target
          /// is private).
          if (!isPrivate || isFollowing) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onMessageTap,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                icon: Icon(Icons.chat_bubble_outline,
                    size: 16, color: context.textPrimary),
                label: Text(context.t.message,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// TABS
class UserTabBar extends StatelessWidget {
  final int selectedTab;
  final Function(int) onTap;

  const UserTabBar({
    super.key,
    required this.selectedTab,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.grid_on,
      Icons.question_answer_outlined,
      Icons.repeat,
    ];
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / icons.length;
          return Stack(
            children: [
              // Animated underline that slides between tabs.
              // `start` mirrors with the (auto-flipped) tab Row in RTL.
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                start: tabWidth * selectedTab,
                bottom: 0,
                width: tabWidth,
                height: 2,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 2,
                    decoration: BoxDecoration(
                      color: context.textPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(icons.length, (index) {
                  final isActive = selectedTab == index;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: isActive ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 220),
                          builder: (context, t, _) {
                            return Transform.scale(
                              scale: 1 + 0.08 * t,
                              child: Icon(
                                icons[index],
                                color: Color.lerp(
                                  context.textSecondary,
                                  context.textPrimary,
                                  t,
                                ),
                                size: 22,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// PRIVATE MESSAGE
class UserPrivateMessage extends StatelessWidget {
  const UserPrivateMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.inputFill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 24, color: context.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.thisAccountIsPrivate,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t.userPrivateFollowPrompt,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
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
