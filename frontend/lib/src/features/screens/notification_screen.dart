import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/notification_providers.dart';
import '../../services/notification_service.dart';
import '../widgets/notification_tile.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (user != null)
                    TextButton(
                      onPressed: () => ref
                          .read(notificationServiceProvider)
                          .markAllRead(user.uid),
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB05ECC),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            /// LIST
            Expanded(
              child: notificationsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (notifications) {
                  if (notifications.isEmpty) {
                    return const Center(
                      child: Text(
                        'No notifications yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: notifications.length,
                    itemBuilder: (_, i) => _NotificationItem(
                      notif: notifications[i],
                      onMarkRead: user == null
                          ? null
                          : () => ref
                              .read(notificationServiceProvider)
                              .markRead(user.uid, notifications[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Private per-item widget
// ─────────────────────────────────────────────

class _NotificationItem extends ConsumerWidget {
  final AppNotification notif;
  final VoidCallback? onMarkRead;

  const _NotificationItem({required this.notif, this.onMarkRead});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorStream =
        ref.watch(userServiceProvider).streamUser(notif.actorUid);
    final currentUser = ref.watch(authStateProvider).value;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: actorStream,
      builder: (context, snapshot) {
        final actor = snapshot.data;
        final avatar = (actor?['avatarUrl'] as String?) ?? '';
        final username = (actor?['username'] as String?) ?? '...';

        String title;
        String subtitle;
        NotificationType trailingType;
        bool isLike = false;
        VoidCallback? onFollow;

        switch (notif.type) {
          case 'follow':
            title = '$username started following you';
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.followBack;
            if (currentUser != null) {
              onFollow = () => ref.read(followServiceProvider).follow(
                    currentUid: currentUser.uid,
                    targetUid: notif.actorUid,
                  );
            }
            break;
          case 'like':
            title = '$username liked your post';
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            isLike = true;
            break;
          case 'comment':
            title = '$username commented on your post';
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          default:
            title = username;
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
        }

        return GestureDetector(
          onTap: onMarkRead,
          child: Opacity(
            opacity: notif.read ? 0.55 : 1.0,
            child: NotificationTile(
              avatar: avatar,
              title: title,
              subtitle: subtitle,
              trailingType: trailingType,
              isLike: isLike,
              onFollowTap: onFollow,
            ),
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }
}
