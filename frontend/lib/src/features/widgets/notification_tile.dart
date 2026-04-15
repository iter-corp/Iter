import 'package:flutter/material.dart';

enum NotificationType { follow, followBack, image }

class NotificationTile extends StatelessWidget {
  final String avatar;
  final String title;
  final String subtitle;
  final String? postImage;
  final bool isLike;
  final NotificationType trailingType;

  /// Called when the Follow / Follow Back button is tapped.
  final VoidCallback? onFollowTap;

  const NotificationTile({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.postImage,
    this.isLike = false,
    required this.trailingType,
    this.onFollowTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          /// AVATAR + LIKE ICON
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey.shade200,
                backgroundImage:
                    avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              if (isLike)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.favorite, size: 12, color: Colors.red),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 12),

          /// TEXT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          /// TRAILING
          _buildTrailing(),
        ],
      ),
    );
  }

  Widget _buildTrailing() {
    switch (trailingType) {
      case NotificationType.followBack:
        return _buildButton('Follow back', onFollowTap);

      case NotificationType.follow:
        return _buildButton('Follow', onFollowTap);

      case NotificationType.image:
        if (postImage == null || postImage!.isEmpty) {
          return const SizedBox(width: 45, height: 45);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            postImage!,
            width: 45,
            height: 45,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(width: 45, height: 45),
          ),
        );
    }
  }

  Widget _buildButton(String text, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFB44FFF),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
