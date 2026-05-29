import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';

/// COVER + AVATAR — uses live profile data
class UserCoverAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? coverUrl;
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
    required this.isPrivate,
    required this.onBack,
    this.showMenu = false,
    this.onBlockTap,
    this.onReportTap,
    this.isBlocked = false,
  });

  ImageProvider? get _avatarImage =>
      (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? CachedNetworkImageProvider(avatarUrl!)
          : null;

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

    final avatar = CircleAvatar(
      radius: 40,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: _avatarImage,
      child: _avatarImage == null
          ? const Icon(Icons.person, size: 40, color: Colors.grey)
          : null,
    );

    if (isPrivate) {
      return SizedBox(
        height: 200,
        child: Stack(
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: (coverUrl != null && coverUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(height: 140, color: context.inputFill),
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
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.cardBg,
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
            child: (coverUrl != null && coverUrl!.isNotEmpty)
                ? CachedNetworkImage(imageUrl: coverUrl!, fit: BoxFit.cover)
                : Container(color: context.inputFill),
          ),
          backArrow,
          menuButton,
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.cardBg,
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
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                bio,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          /// FOLLOW BUTTON
          Expanded(
            child: SizedBox(
              height: 40,
              child: GestureDetector(
                onTap: onFollowTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: active ? context.cardBg : const Color(0xFFB05ECC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active
                          ? context.borderColor
                          : const Color(0xFFB05ECC),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: active ? context.textPrimary : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          /// MESSAGE BUTTON — shown for public profiles, AND for
          /// private profiles once the follow has been accepted (so
          /// mutual followers can DM each other even when the target
          /// is private).
          if (!isPrivate || isFollowing) ...[
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: onMessageTap,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.t.message,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
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
    final icons = [
      Icons.grid_on,
      Icons.question_answer_outlined,
      Icons.repeat,
    ];

    return Row(
      children: List.generate(icons.length, (index) {
        final bool isActive = selectedTab == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? context.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Icon(
                icons[index],
                color: isActive ? context.textPrimary : context.textSecondary,
                size: 22,
              ),
            ),
          ),
        );
      }),
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
