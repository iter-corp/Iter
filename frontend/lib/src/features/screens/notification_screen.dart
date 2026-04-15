import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/notification_providers.dart';
import '../../services/notification_service.dart';
import '../widgets/notification_tile.dart';
import 'chat_screen.dart';
import 'post_detail_screen.dart';
import 'user_screen.dart';

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
                      onDelete: user == null
                          ? null
                          : () => ref
                              .read(notificationServiceProvider)
                              .deleteNotification(
                                  user.uid, notifications[i].id),
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
  final VoidCallback? onDelete;

  const _NotificationItem({
    required this.notif,
    this.onMarkRead,
    this.onDelete,
  });

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
          case 'message':
            title = '$username sent you a message';
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          default:
            title = username;
            subtitle = _timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
        }

        // Build the trailing widget for like/comment (post thumbnail).
        Widget? trailingWidget;
        if ((notif.type == 'like' || notif.type == 'comment') &&
            notif.targetId != null) {
          trailingWidget = _PostThumbnail(postId: notif.targetId!);
        }

        return Dismissible(
          key: ValueKey(notif.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red.shade400,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => onDelete?.call(),
          child: GestureDetector(
            onTap: () {
              onMarkRead?.call();
              _navigateToTarget(context, notif);
            },
            child: Opacity(
              opacity: notif.read ? 0.55 : 1.0,
              child: NotificationTile(
                avatar: avatar,
                title: title,
                subtitle: subtitle,
                trailingType: trailingType,
                isLike: isLike,
                onFollowTap: onFollow,
                trailingWidget: trailingWidget,
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateToTarget(BuildContext context, AppNotification notif) {
    switch (notif.type) {
      case 'follow':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(uid: notif.actorUid),
          ),
        );
        break;
      case 'like':
      case 'comment':
        if (notif.targetId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailScreen(postId: notif.targetId!),
            ),
          );
        }
        break;
      case 'message':
        if (notif.targetId != null) {
          _openChatFromNotification(context, notif);
        }
        break;
    }
  }

  /// Resolves the chat metadata + actor info, then navigates to ChatScreen.
  Future<void> _openChatFromNotification(
    BuildContext context,
    AppNotification notif,
  ) async {
    final db = FirebaseFirestore.instance;
    // Fetch actor (the sender) info for ChatScreen header.
    final actorSnap =
        await db.collection('users').doc(notif.actorUid).get();
    final actorData = actorSnap.data() ?? {};
    final otherName = (actorData['username'] as String?) ?? 'User';
    final otherAvatar = (actorData['avatarUrl'] as String?) ?? '';

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: notif.targetId!,
          otherUid: notif.actorUid,
          otherName: otherName,
          otherAvatar: otherAvatar,
        ),
      ),
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

// ─────────────────────────────────────────────
// Post thumbnail — loads the first image from a post
// ─────────────────────────────────────────────

class _PostThumbnail extends StatelessWidget {
  final String postId;
  const _PostThumbnail({required this.postId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('posts').doc(postId).get(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox(width: 45, height: 45);
        }
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final images = (data['imageUrls'] as List<dynamic>?) ?? [];
        if (images.isEmpty) {
          return const SizedBox(width: 45, height: 45);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: images.first as String,
            width: 45,
            height: 45,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                const SizedBox(width: 45, height: 45),
          ),
        );
      },
    );
  }
}

