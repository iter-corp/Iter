import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';

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

  /// Optional custom trailing widget (e.g. a post thumbnail loaded from Firestore).
  /// When provided, this overrides the default [trailingType == image] rendering.
  final Widget? trailingWidget;

  const NotificationTile({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.postImage,
    this.isLike = false,
    required this.trailingType,
    this.onFollowTap,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Each notification renders as a floating rounded card, matching
    // the share-recipient cards used in the post / story share sheets.
    // The list itself supplies vertical spacing via item separators;
    // here we only carry horizontal margin + the chrome.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Container(
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
            /// AVATAR — gradient ring around the user picture, mirrors
            /// the share-recipient card. The small heart badge for like
            /// notifications still sits on top of the ring.
            Stack(
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
                    backgroundImage: avatar.isNotEmpty
                        ? CachedNetworkImageProvider(avatar)
                        : null,
                    child: avatar.isEmpty
                        ? Icon(Icons.person, color: context.textMuted)
                        : null,
                  ),
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

            /// TEXT — title up to 2 lines + 1-line subtitle. Long
            /// localized strings (Kurdish / Arabic) ellipsis instead of
            /// overflowing the row.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            /// TRAILING
            _buildTrailing(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    // Allow caller to override the trailing area for any notification type.
    if (trailingWidget != null) return trailingWidget!;

    switch (trailingType) {
      case NotificationType.followBack:
        return _buildButton(context, context.t.notifFollowBack, onFollowTap);

      case NotificationType.follow:
        return _buildButton(context, context.t.notifFollow, onFollowTap);

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

  Widget _buildButton(BuildContext context, String text, VoidCallback? onTap) {
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
