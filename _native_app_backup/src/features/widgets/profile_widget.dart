import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../screens/create_post_screen.dart';
import '../screens/edit_profile.dart';

/// Extracts the first character from a display name or username.
/// Handles Unicode/runes safely (Arabic, Kurdish, Latin, etc.) and falls back to 'U'.
String getProfileInitial(String? name) {
  if (name == null) return 'U';
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'U';
  final firstChar = String.fromCharCode(trimmed.runes.first);
  return firstChar.toUpperCase();
}

/// Fallback Cover Gradient shown when a cover is missing or fails to load.
class ProfileDefaultCover extends StatelessWidget {
  final double height;
  final double? width;
  const ProfileDefaultCover({
    super.key,
    this.height = 180,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF2E1065), // Deep purple
                  Color(0xFF4C1D95), // Violet
                  Color(0xFF6B21A8), // Purple
                  Color(0xFF1E1B4B), // Indigo dark
                ]
              : const [
                  Color(0xFFE9D5FF), // Soft lavender
                  Color(0xFFC084FC), // Lilac
                  Color(0xFFA855F7), // Purple 500
                  Color(0xFF818CF8), // Indigo 400
                ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: isDark ? 0.07 : 0.20),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: 30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isDark ? const Color(0xFFC084FC) : Colors.white)
                    .withValues(alpha: isDark ? 0.08 : 0.16),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.04 : 0.12),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback Avatar displaying the user's first initial on a premium gradient.
class ProfileInitialAvatar extends StatelessWidget {
  final String? name;
  final double radius;
  final double? fontSize;

  const ProfileInitialAvatar({
    super.key,
    this.name,
    this.radius = 40,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final initial = getProfileInitial(name);
    final size = radius * 2;
    final fSize = fontSize ?? (radius * 0.82);

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFBA68C8), // Light vibrant purple
            Color(0xFF8E24AA), // Deep purple
            Color(0xFF4A148C), // Royal violet
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: fSize,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// COVER + AVATAR
class ProfileCoverAvatar extends StatelessWidget {
  final String? coverUrl;
  final String? avatarUrl;
  final String? name;

  const ProfileCoverAvatar({
    super.key,
    this.coverUrl,
    this.avatarUrl,
    this.name,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover = coverUrl != null && coverUrl!.trim().isNotEmpty;
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Stack(
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
        Positioned(
          bottom: -40,
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
              child: hasAvatar
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
                  : ProfileInitialAvatar(name: name, radius: 40),
            ),
          ),
        ),
      ],
    );
  }
}

/// NAME + BIO
class ProfileNameBio extends StatelessWidget {
  final String name;
  final String handle;
  final String bio;
  final String profession;
  final String educationLevel;
  final String fieldOfStudy;
  const ProfileNameBio({
    super.key,
    required this.name,
    required this.handle,
    required this.bio,
    this.profession = '',
    this.educationLevel = '',
    this.fieldOfStudy = '',
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
          Text(name,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary)),
          if (handle.trim().isNotEmpty) ...[
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
class ProfileStats extends StatelessWidget {
  final int followers;
  final int following;
  final int posts;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  const ProfileStats({
    super.key,
    required this.followers,
    required this.following,
    required this.posts,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(
              _fmt(followers), context.t.followers, onFollowersTap, context),
          _divider(context),
          _statItem(
              _fmt(following), context.t.following, onFollowingTap, context),
          _divider(context),
          _statItem(_fmt(posts), context.t.posts, null, context),
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
      String value, String label, VoidCallback? onTap, BuildContext context) {
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

/// EDIT PROFILE + SETTING + INVITE BUTTONS
class ProfileButtons extends StatelessWidget {
  final VoidCallback? onSettings;
  final VoidCallback? onInvite;
  final bool showSettingsNotificationDot;
  const ProfileButtons({
    super.key,
    this.onSettings,
    this.onInvite,
    this.showSettingsNotificationDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EditProfileScreen(),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.borderColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              icon: Icon(Icons.edit_outlined,
                  size: 16, color: context.textPrimary),
              label: Text(context.t.editProfile,
                  style: TextStyle(
                      color: context.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSettings,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.settings, size: 16, color: context.textPrimary),
                  if (showSettingsNotificationDot)
                    PositionedDirectional(
                      end: -4,
                      top: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE04E5C),
                          shape: BoxShape.circle,
                          border: Border.all(color: context.cardBg, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
              label: Text(context.t.settings,
                  style: TextStyle(
                      color: context.textPrimary, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.borderColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (onInvite != null) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: context.t.profileInviteFriends,
              child: OutlinedButton(
                onPressed: onInvite,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                ),
                child:
                    Icon(Icons.ios_share, size: 18, color: context.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// TABS — animated pill underline + colour fade. The selected tab
/// glides under the icons rather than snapping, giving the profile a
/// more "modern" feel when switching between sections.
class ProfileTabBar extends StatelessWidget {
  final int selectedTab;
  final Function(int) onTap;

  const ProfileTabBar({
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
      Icons.bookmark_border,
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

/// EMPTY STATE
class ProfileEmpty extends StatelessWidget {
  const ProfileEmpty({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 48, color: context.textSecondary),
            const SizedBox(height: 12),
            Text(context.t.profileCreateFirstPost,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: context.textPrimary)),
            const SizedBox(height: 4),
            Text(context.t.profileShareYourContent,
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            Builder(builder: (ctx) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const CreatePostScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB05ECC),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                ),
                child: Text(ctx.t.profileCreate,
                    style: const TextStyle(color: Colors.white)),
              );
            }),
          ],
        ),
      ),
    );
  }
}
