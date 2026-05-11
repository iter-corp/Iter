import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../screens/create_post_screen.dart';
import '../screens/edit_profile.dart';

/// COVER + AVATAR
class ProfileCoverAvatar extends StatelessWidget {
  final String? coverUrl;
  final String? avatarUrl;
  const ProfileCoverAvatar({super.key, this.coverUrl, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: coverUrl != null
              ? CachedNetworkImage(imageUrl: coverUrl!, fit: BoxFit.cover)
              : Container(color: context.inputFill),
        ),
        Positioned(
          bottom: -40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.cardBg,
              ),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: context.inputFill,
                backgroundImage: avatarUrl != null
                    ? CachedNetworkImageProvider(avatarUrl!)
                    : null,
                child: avatarUrl == null
                    ? Icon(Icons.person, size: 40, color: context.textMuted)
                    : null,
              ),
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
  const ProfileNameBio({
    super.key,
    required this.name,
    required this.handle,
    required this.bio,
  });

  @override
  Widget build(BuildContext context) {
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
              handle,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(bio,
              style: TextStyle(fontSize: 13, color: context.textSecondary)),
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
          _statItem(_fmt(followers), "Followers", onFollowersTap, context),
          _divider(context),
          _statItem(_fmt(following), "Following", onFollowingTap, context),
          _divider(context),
          _statItem(_fmt(posts), "Posts", null, context),
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
  const ProfileButtons({super.key, this.onSettings, this.onInvite});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
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
              child: Text("Edit Profile",
                  style: TextStyle(
                      color: context.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSettings,
              icon: Icon(Icons.settings, size: 16, color: context.textPrimary),
              label: Text("Setting",
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
              message: 'Invite friends',
              child: OutlinedButton(
                onPressed: onInvite,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 14),
                ),
                child: Icon(Icons.ios_share,
                    size: 18, color: context.textPrimary),
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
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: tabWidth * selectedTab,
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
            Text("Create your first post",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: context.textPrimary)),
            const SizedBox(height: 4),
            Text("Share your content",
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
                child:
                    const Text("Create", style: TextStyle(color: Colors.white)),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// BOTTOM NAV
class ProfileBottomNav extends StatelessWidget {
  final int selectedNav;
  final Function(int) onTap;
  final List<String> icons;

  const ProfileBottomNav({
    super.key,
    required this.selectedNav,
    required this.onTap,
    required this.icons,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(icons.length, (index) {
            final bool isSelected = selectedNav == index;
            return GestureDetector(
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: SvgPicture.asset(
                  icons[index],
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    isSelected ? Colors.black : Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
