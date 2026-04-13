import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
              : Container(color: const Color(0xFFF0F0F0)),
        ),
        Positioned(
          bottom: -40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: avatarUrl != null
                    ? CachedNetworkImageProvider(avatarUrl!)
                    : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 40, color: Colors.grey)
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
  final String bio;
  const ProfileNameBio({super.key, required this.name, required this.bio});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 52, bottom: 8),
      child: Column(
        children: [
          Text(name,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(bio, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
          _statItem(_fmt(followers), "Followers", onFollowersTap),
          _divider(),
          _statItem(_fmt(following), "Following", onFollowingTap),
          _divider(),
          _statItem(_fmt(posts), "Posts", null),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _statItem(String value, String label, VoidCallback? onTap) {
    final content = Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8), child: content);
  }

  Widget _divider() =>
      Container(width: 1, height: 36, color: Colors.grey.shade300);
}

/// EDIT PROFILE + SETTING BUTTONS
class ProfileButtons extends StatelessWidget {
  final VoidCallback? onSettings;
  const ProfileButtons({super.key, this.onSettings});

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
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child: const Text("Edit Profile",
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.settings, size: 16, color: Colors.black),
              label: const Text("Setting",
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TABS
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
    return Row(
      children: [
        _tab(Icons.grid_on, 0),
        _tab(Icons.repeat, 1),
        _tab(Icons.bookmark_border, 2),
      ],
    );
  }

  Widget _tab(IconData icon, int index) {
    final bool isActive = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isActive ? Colors.black : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.black : Colors.grey,
            size: 22,
          ),
        ),
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
            const Icon(Icons.image_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text("Create your first post",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            const Text("Share your content",
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB05ECC),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              ),
              child:
                  const Text("Create", style: TextStyle(color: Colors.white)),
            ),
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
