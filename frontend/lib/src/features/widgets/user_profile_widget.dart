import 'package:flutter/material.dart';
import 'dart:ui';

/// COVER + AVATAR
class UserCoverAvatar extends StatelessWidget {
  final String avatar;
  final List<String> posts;
  final bool isPrivate;
  final VoidCallback onBack;

  const UserCoverAvatar({
    super.key,
    required this.avatar,
    required this.posts,
    required this.isPrivate,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final coverImage = posts.isNotEmpty ? posts.first : "assets/img/2.png";

    if (isPrivate) {
      return SizedBox(
        height: 200,
        child: Stack(
          children: [
            /// BLURRED COVER IMAGE
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Image.asset(
                  "assets/img/2.png",
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            /// DARK OVERLAY
            Container(
              height: 140,
              color: Colors.black.withOpacity(0.2),
            ),

            /// BACK ARROW
            Positioned(
              top: 40,
              left: 12,
              child: GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
            ),

            /// AVATAR
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const CircleAvatar(
                    radius: 40,
                    backgroundImage: AssetImage("assets/img/2.png"),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    /// PUBLIC
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Image.asset(
          coverImage,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
        ),

        /// BACK ARROW
        Positioned(
          top: 40,
          left: 12,
          child: GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
        ),

        /// AVATAR
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
              child: const CircleAvatar(
                radius: 40,
                backgroundImage: AssetImage("assets/img/1.png"),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// NAME + BIO
class UserNameBio extends StatelessWidget {
  final String username;
  final String handle;

  const UserNameBio({
    super.key,
    required this.username,
    required this.handle,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 52, bottom: 8),
      child: Column(
        children: [
          Text(
            username,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            handle,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
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

  const UserStats({
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

/// FOLLOW + MESSAGE BUTTONS
class UserButtons extends StatelessWidget {
  final bool isFollowing;
  final bool isPrivate;
  final VoidCallback onFollowTap;

  const UserButtons({
    super.key,
    required this.isFollowing,
    required this.isPrivate,
    required this.onFollowTap,
  });

  @override
  Widget build(BuildContext context) {
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
                    color: isFollowing ? Colors.white : const Color(0xFFB05ECC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isFollowing
                          ? Colors.grey.shade300
                          : const Color(0xFFB05ECC),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isFollowing ? "Following" : "Follow",
                      style: TextStyle(
                        color: isFollowing ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          /// MESSAGE BUTTON — only for public
          if (!isPrivate) ...[
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    "Message",
                    style: TextStyle(
                      color: Colors.black,
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
      Icons.repeat,
    ];

    return Row(
      children: List.generate(2, (index) {
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
                icons[index],
                color: isActive ? Colors.black : Colors.grey,
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
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, size: 24, color: Colors.black),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "This account is private",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Follow this account to see their contents.",
                    style: TextStyle(
                      color: Colors.grey,
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
