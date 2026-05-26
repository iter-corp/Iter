import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/notification_providers.dart';
import '../model/post_model.dart';
import '../../services/admin_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/event_detail.dart';
import '../widgets/event_unavailable_screen.dart';
import '../widgets/notification_tile.dart';
import 'chat_screen.dart';
import 'event_chat_screen.dart';
import 'event_screen.dart';
import 'post_detail_screen.dart';
import 'qa_thread_screen.dart';
import 'user_screen.dart';

enum _NotificationCategory { activity, follow, event }

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  _NotificationCategory _selectedCategory = _NotificationCategory.activity;

  /// One-shot guard: auto-mark-all-as-read happens exactly once per screen
  /// mount, on the first frame. Without the guard, [build] could re-trigger
  /// the bulk update every time the notifications stream emits.
  bool _autoMarkedRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoMarkAllReadOnce();
    });
  }

  Future<void> _autoMarkAllReadOnce() async {
    if (_autoMarkedRead || !mounted) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    _autoMarkedRead = true;
    try {
      await ref.read(notificationServiceProvider).markAllRead(user.uid);
    } catch (_) {
      // Best-effort — failure here shouldn't block the user from seeing
      // the screen. Snapshot will still surface notifications as-is.
    }
  }

  Future<void> _showItemActions(AppNotification notif) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  notif.read
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                ),
                title: Text(
                  notif.read
                      ? context.t.notifMarkAsUnread
                      : context.t.notifMarkAsRead,
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final service = ref.read(notificationServiceProvider);
                  if (notif.read) {
                    await service.markUnread(user.uid, notif.id);
                  } else {
                    await service.markRead(user.uid, notif.id);
                  }
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(
                  context.t.notifDelete,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await ref
                        .read(notificationServiceProvider)
                        .deleteNotification(user.uid, notif.id);
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  _NotificationCategory _categoryForType(String type) {
    switch (type) {
      case 'follow':
      case 'follow_request':
      case 'follow_accept':
        return _NotificationCategory.follow;
      case 'event_approved':
      case 'event_rejected':
      case 'event_invited':
      case 'event_removed':
      case 'new_event':
      case 'role_update':
        return _NotificationCategory.event;
      default:
        return _NotificationCategory.activity;
    }
  }

  Map<_NotificationCategory, int> _buildUnreadCounts({
    required List<AppNotification> notifications,
    required List<String> followRequests,
  }) {
    final counts = <_NotificationCategory, int>{
      _NotificationCategory.activity: 0,
      _NotificationCategory.follow: 0,
      _NotificationCategory.event: 0,
    };

    for (final notification in notifications.where((n) => !n.read)) {
      final category = _categoryForType(notification.type);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final persistedRequestActors = notifications
        .where((n) => n.type == 'follow_request')
        .map((n) => n.actorUid)
        .toSet();

    final syntheticFollowUnread = followRequests
        .where((uid) => !persistedRequestActors.contains(uid))
        .length;

    counts[_NotificationCategory.follow] =
        (counts[_NotificationCategory.follow] ?? 0) + syntheticFollowUnread;

    return counts;
  }

  bool _matchesCategory(AppNotification notification) {
    switch (_selectedCategory) {
      case _NotificationCategory.activity:
        return notification.type == 'like' ||
            notification.type == 'reply' ||
            notification.type == 'comment' ||
            notification.type == 'comment_like' ||
            notification.type == 'qa_answer' ||
            notification.type == 'qa_reply' ||
            notification.type == 'qa_answer_like' ||
            notification.type == 'qa_answer_dislike' ||
            notification.type == 'repost' ||
            notification.type == 'story_like' ||
            notification.type == 'story_comment' ||
            notification.type == 'story_reply' ||
            notification.type == 'message';
      case _NotificationCategory.follow:
        return notification.type == 'follow' ||
            notification.type == 'follow_request' ||
            notification.type == 'follow_accept';
      case _NotificationCategory.event:
        return notification.type == 'event_approved' ||
            notification.type == 'event_rejected' ||
            notification.type == 'event_invited' ||
            notification.type == 'event_removed' ||
            notification.type == 'new_event' ||
            notification.type == 'role_update';
    }
  }

  String _emptyLabel(BuildContext context) {
    switch (_selectedCategory) {
      case _NotificationCategory.activity:
        return context.t.notifNoActivity;
      case _NotificationCategory.follow:
        return context.t.notifNoFollow;
      case _NotificationCategory.event:
        return context.t.notifNoEvent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final user = ref.watch(authStateProvider).value;
    final followRequestsAsync = user == null
        ? const AsyncData<List<String>>(<String>[])
        : ref.watch(followRequestsProvider(user.uid));
    final notifications =
        notificationsAsync.valueOrNull ?? const <AppNotification>[];
    final followRequests = followRequestsAsync.valueOrNull ?? const <String>[];
    final unreadByCategory = _buildUnreadCounts(
      notifications: notifications,
      followRequests: followRequests,
    );

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              // Notifications are auto-marked read on screen open, so the
              // "Mark all read" button used to live here is gone. Title
              // wrapped in Expanded with ellipsis for long localized labels
              // (Kurdish/Arabic translations otherwise overflowed the row).
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.notifications,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CategoryChip(
                      label: context.t.notifCategoryActivity,
                      selected:
                          _selectedCategory == _NotificationCategory.activity,
                      unreadCount:
                          unreadByCategory[_NotificationCategory.activity] ?? 0,
                      onTap: () => setState(() {
                        _selectedCategory = _NotificationCategory.activity;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: context.t.notifCategoryFollow,
                      selected:
                          _selectedCategory == _NotificationCategory.follow,
                      unreadCount:
                          unreadByCategory[_NotificationCategory.follow] ?? 0,
                      onTap: () => setState(() {
                        _selectedCategory = _NotificationCategory.follow;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: context.t.notifCategoryEvent,
                      selected:
                          _selectedCategory == _NotificationCategory.event,
                      unreadCount:
                          unreadByCategory[_NotificationCategory.event] ?? 0,
                      onTap: () => setState(() {
                        _selectedCategory = _NotificationCategory.event;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            /// LIST
            Expanded(
              child: notificationsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(context.t.errorWithMessage(e))),
                data: (notifications) {
                  final followRequests =
                      followRequestsAsync.valueOrNull ?? const <String>[];
                  final existingRequestActors = notifications
                      .where((n) => n.type == 'follow_request')
                      .map((n) => n.actorUid)
                      .toSet();

                  // Fallback source for pending requests when notification docs
                  // are missing (for example on Spark-only setups).
                  final syntheticRequests = followRequests
                      .where((uid) => !existingRequestActors.contains(uid))
                      .map(
                        (uid) => AppNotification(
                          id: 'follow_request_$uid',
                          type: 'follow_request',
                          actorUid: uid,
                          targetId: uid,
                          read: false,
                          createdAt: null,
                        ),
                      )
                      .toList();

                  final items = <AppNotification>[
                    ...syntheticRequests,
                    ...notifications,
                  ].where(_matchesCategory).toList();

                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        _emptyLabel(context),
                        style: TextStyle(color: context.textMuted),
                      ),
                    );
                  }

                  final persistedIds = notifications.map((n) => n.id).toSet();

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _NotificationItem(
                      notif: items[i],
                      onMarkRead: user == null
                          ? null
                          : persistedIds.contains(items[i].id)
                              ? () => ref
                                  .read(notificationServiceProvider)
                                  .markRead(user.uid, items[i].id)
                              : null,
                      onDelete: user == null
                          ? null
                          : persistedIds.contains(items[i].id)
                              ? () => ref
                                  .read(notificationServiceProvider)
                                  .deleteNotification(user.uid, items[i].id)
                              : null,
                      onLongPress: persistedIds.contains(items[i].id)
                          ? () => _showItemActions(items[i])
                          : null,
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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final int unreadCount;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? const Color(0xFFB44FFF) : context.cardBg,
          border: Border.all(
            color: selected ? const Color(0xFFB44FFF) : context.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.textPrimary,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : const Color(0xFFFF4D4D),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? const Color(0xFFFF4D4D) : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Private per-item widget
// ─────────────────────────────────────────────

class _FollowStateButton extends StatelessWidget {
  final bool isFollowing;
  final VoidCallback? onTap;

  const _FollowStateButton({
    required this.isFollowing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isFollowing ? context.borderColor : const Color(0xFFB44FFF),
        ),
        child: Text(
          isFollowing ? context.t.notifFollowing : context.t.notifFollowBack,
          style: TextStyle(
            color: isFollowing ? context.textPrimary : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _NotificationItem extends ConsumerWidget {
  final AppNotification notif;
  final VoidCallback? onMarkRead;
  final VoidCallback? onDelete;
  final VoidCallback? onLongPress;

  const _NotificationItem({
    required this.notif,
    this.onMarkRead,
    this.onDelete,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // System notifications (e.g. `new_event`) carry an empty actorUid since
    // they aren't attributable to a specific user. Calling streamUser('')
    // throws "A document path must be a non-empty string". Skip the lookup
    // entirely in that case — `new_event` renders title/subtitle from the
    // notification doc itself and doesn't need actor info.
    final hasActor = notif.actorUid.isNotEmpty;
    final actorStream = hasActor
        ? ref.watch(userServiceProvider).streamUser(notif.actorUid)
        : Stream<Map<String, dynamic>?>.value(null);
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
        Widget? trailingWidget;

        switch (notif.type) {
          case 'follow':
            title = context.t.notifStartedFollowing(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.followBack;
            if (currentUser != null) {
              onFollow = () => ref.read(followServiceProvider).follow(
                    currentUid: currentUser.uid,
                    targetUid: notif.actorUid,
                    isPrivate: false,
                  );

              final isFollowingAsync =
                  ref.watch(isFollowingProvider(notif.actorUid));
              final isFollowing =
                  isFollowingAsync.whenOrNull(data: (v) => v) ?? false;

              trailingWidget = _FollowStateButton(
                isFollowing: isFollowing,
                onTap: isFollowing ? null : onFollow,
              );
            }
            break;
          case 'follow_request':
            title = context.t.notifRequestedToFollow(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            if (currentUser != null) {
              final followRequestsAsync =
                  ref.watch(followRequestsProvider(currentUser.uid));
              final followersAsync =
                  ref.watch(followersProvider(currentUser.uid));

              final followRequests = followRequestsAsync.valueOrNull;
              final followers = followersAsync.valueOrNull;

              if (followRequests == null || followers == null) {
                trailingWidget = const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2));
              } else {
                final isPending = followRequests.contains(notif.actorUid);
                final isFollower = followers.contains(notif.actorUid);

                // Show action buttons only if request is still pending
                if (isPending && !isFollower) {
                  trailingWidget = _FollowRequestActions(
                    requesterUid: notif.actorUid,
                    currentUid: currentUser.uid,
                  );
                } else {
                  // Request was already processed (accepted or rejected)
                  trailingWidget = Text(
                    isFollower
                        ? context.t.notifAccepted
                        : context.t.notifRejected,
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  );
                }
              }
            }
            break;
          case 'like':
            title = context.t.notifLikedYourPost(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            isLike = true;
            break;
          case 'comment_like':
            title = context.t.notifLikedYourComment(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            isLike = true;
            break;
          case 'comment':
            title = context.t.notifCommentedOnPost(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'reply':
            title = context.t.notifRepliedToComment(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'qa_answer':
            title = context.t.notifAnsweredQuestion(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'qa_reply':
            title = context.t.notifRepliedToAnswer(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'qa_answer_like':
            title = context.t.notifLikedYourAnswer(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            isLike = true;
            break;
          case 'qa_answer_dislike':
            title = context.t.notifDislikedYourAnswer(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'message':
            title = context.t.notifSentYouMessage(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'event_approved':
            title = context.t.notifEventApproved;
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'event_rejected':
            title = context.t.notifEventRejected;
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'event_invited':
            title = context.t.notifAddedToEventGroup(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'event_removed':
            title = context.t.notifRemovedFromEventGroup;
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          case 'new_event':
            final eventName = (notif.title ?? '').trim();
            title = eventName.isEmpty
                ? context.t.notifNewEventPublished
                : context.t.notifNewEventNamed(eventName);
            final loc = (notif.subtitle ?? '').trim();
            subtitle = loc.isEmpty
                ? context.t.timeAgo(notif.createdAt)
                : '$loc · ${context.t.timeAgo(notif.createdAt)}';
            trailingType = NotificationType.image;
            break;
          case 'role_update':
            title = (notif.title ?? '').trim().isEmpty
                ? 'Your role was updated'
                : notif.title!.trim();
            final details = (notif.subtitle ?? '').trim();
            subtitle = details.isEmpty
                ? context.t.timeAgo(notif.createdAt)
                : '$details · ${context.t.timeAgo(notif.createdAt)}';
            trailingType = NotificationType.image;
            break;
          case 'follow_accept':
            title = context.t.notifAcceptedFollowRequest(username);
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
            break;
          default:
            title = username;
            subtitle = context.t.timeAgo(notif.createdAt);
            trailingType = NotificationType.image;
        }

        // Build the trailing widget for like/comment (post thumbnail).
        if ((notif.type == 'like' ||
                notif.type == 'comment' ||
                notif.type == 'comment_like' ||
                notif.type == 'reply' ||
                notif.type == 'qa_answer' ||
                notif.type == 'qa_reply' ||
                notif.type == 'qa_answer_like' ||
                notif.type == 'qa_answer_dislike') &&
            notif.targetId != null) {
          trailingWidget = _PostThumbnail(postId: notif.targetId!);
        }

        // Inline accept/reject buttons for event invitations.
        if (notif.type == 'event_invited' && notif.targetId != null) {
          trailingWidget = _InviteActions(
            eventId: notif.targetId!,
            onDone: onMarkRead,
          );
        }

        final tile = GestureDetector(
          onTap: () {
            onMarkRead?.call();
            _navigateToTarget(context, notif);
          },
          // Long-press reveals per-notification actions: toggle read state
          // (so users can mark a swept-read item back to unread) and delete.
          onLongPress: onLongPress,
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
        );

        if (notif.type == 'follow_request') {
          return tile;
        }

        return Dismissible(
          key: ValueKey(notif.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: 20),
            color: Colors.red.shade400,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => onDelete?.call(),
          child: tile,
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
      case 'reply':
      case 'qa_answer':
      case 'qa_reply':
      case 'qa_answer_like':
      case 'qa_answer_dislike':
        if (notif.targetId != null) {
          _openPostTarget(
            context,
            notif.targetId!,
            highlightCommentId: notif.commentId,
            highlightAuthorUid: notif.actorUid,
          );
        }
        break;
      case 'comment_like':
        if (notif.targetId != null) {
          _openPostTarget(
            context,
            notif.targetId!,
            highlightCommentId: notif.commentId,
            highlightAuthorUid: notif.actorUid,
          );
        }
        break;
      case 'message':
        if (notif.targetId != null) {
          _openChatFromNotification(context, notif);
        }
        break;
      case 'event_approved':
      case 'event_invited':
        if (notif.targetId != null) {
          _openEventChatFromNotification(context, notif);
        }
        break;
      case 'new_event':
        // Jump straight to the event detail. Falls back to the events list
        // if the event was deleted/unpublished between fan-out and tap.
        if (notif.targetId != null && notif.targetId!.isNotEmpty) {
          _openEventDetailFromNotification(context, notif.targetId!);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EventBody()),
          );
        }
        break;
      case 'event_rejected':
      case 'event_removed':
      case 'role_update':
        // Nothing to navigate to — the user is no longer in the group.
        break;
    }
  }

  Future<void> _openPostTarget(
    BuildContext context,
    String postId, {
    String? highlightCommentId,
    String? highlightAuthorUid,
  }) async {
    final snap =
        await FirebaseFirestore.instance.collection('posts').doc(postId).get();
    if (!context.mounted) return;

    if (!snap.exists) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            postId: postId,
            highlightCommentId: highlightCommentId,
          ),
        ),
      );
      return;
    }

    final data = snap.data() ?? {};
    final isQa = (data['postType'] as String?) == 'qa';
    if (isQa) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QaThreadScreen(
            post: Post.fromDoc(snap),
            highlightAuthorUid: highlightAuthorUid,
            highlightCommentId: highlightCommentId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: postId,
          highlightCommentId: highlightCommentId,
        ),
      ),
    );
  }

  /// Loads the event doc from Firestore and pushes [EventDetailScreen].
  /// If the event is gone (deleted by the admin between fan-out and tap)
  /// we show a dedicated unavailable screen.
  Future<void> _openEventDetailFromNotification(
    BuildContext context,
    String eventId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .get();
    if (!context.mounted) return;
    if (!snap.exists) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EventUnavailableScreen()),
      );
      return;
    }
    final e = AdminEvent.fromDoc(snap);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: e.id,
          title: e.title,
          subtitle: e.subtitle,
          location: e.location,
          eventType: e.eventType,
          funds: e.funds,
          deadlineAt: e.deadlineAt,
          imageUrls: e.imageUrls,
          description: e.description,
          link: e.link,
          phone: e.phone,
          email: e.email,
          createdByUid: e.createdByUid,
        ),
      ),
    );
  }

  /// Resolves the event chat metadata and navigates into it.
  Future<void> _openEventChatFromNotification(
    BuildContext context,
    AppNotification notif,
  ) async {
    final db = FirebaseFirestore.instance;
    final snap = await db.collection('eventChats').doc(notif.targetId!).get();
    final d = snap.data() ?? {};
    final adminUid = (d['adminUid'] as String?) ?? '';

    if (!context.mounted) return;
    final title =
        (d['eventTitle'] as String?) ?? context.t.notifEventFallbackTitle;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventChatScreen(
          eventId: notif.targetId!,
          eventTitle: title,
          adminUid: adminUid,
        ),
      ),
    );
  }

  /// Resolves the chat metadata + actor info, then navigates to ChatScreen.
  Future<void> _openChatFromNotification(
    BuildContext context,
    AppNotification notif,
  ) async {
    final db = FirebaseFirestore.instance;
    // Fetch actor (the sender) info for ChatScreen header.
    final actorSnap = await db.collection('users').doc(notif.actorUid).get();
    final actorData = actorSnap.data() ?? {};
    final otherAvatar = (actorData['avatarUrl'] as String?) ?? '';

    if (!context.mounted) return;
    final otherName =
        (actorData['username'] as String?) ?? context.t.notifUserFallback;

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

}

// ─────────────────────────────────────────────
// Invite actions — Accept (stay in the group) / Reject (leave the group).
// Shown inline on `event_invited` notifications.
// ─────────────────────────────────────────────

class _InviteActions extends ConsumerStatefulWidget {
  final String eventId;
  final VoidCallback? onDone;

  const _InviteActions({required this.eventId, this.onDone});

  @override
  ConsumerState<_InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends ConsumerState<_InviteActions> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventChatServiceProvider).leaveGroup(widget.eventId);
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.failedWithError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _busy ? null : _reject,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE04E5C)),
            ),
            child: Text(
              context.t.notifReject,
              style: const TextStyle(
                  color: Color(0xFFE04E5C),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: _busy ? null : _accept,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFB44FFF),
            ),
            child: Text(
              context.t.notifAccept,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Follow Request actions
// ─────────────────────────────────────────────

class _FollowRequestActions extends ConsumerStatefulWidget {
  final String requesterUid;
  final String currentUid;

  const _FollowRequestActions({
    required this.requesterUid,
    required this.currentUid,
  });

  @override
  ConsumerState<_FollowRequestActions> createState() =>
      _FollowRequestActionsState();
}

class _FollowRequestActionsState extends ConsumerState<_FollowRequestActions> {
  bool _busy = false;
  bool _success = false;

  Future<void> _accept() async {
    if (_busy || _success) return;
    setState(() => _busy = true);
    try {
      await ref.read(followServiceProvider).acceptFollowRequest(
            currentUid: widget.currentUid,
            requesterUid: widget.requesterUid,
          );

      // Delete the follow request notification using the deterministic ID that matches the backend
      // The backend creates notifications with ID format: follow_request_${followerUid}
      final deterministicNotificationId =
          'follow_request_${widget.requesterUid}';
      await ref.read(notificationServiceProvider).deleteNotification(
            widget.currentUid,
            deterministicNotificationId,
          );

      if (mounted) setState(() => _success = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.failedWithError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy || _success) return;
    setState(() => _busy = true);
    try {
      await ref.read(followServiceProvider).rejectFollowRequest(
            currentUid: widget.currentUid,
            requesterUid: widget.requesterUid,
          );

      // Delete the follow request notification using the deterministic ID that matches the backend
      // The backend creates notifications with ID format: follow_request_${followerUid}
      final deterministicNotificationId =
          'follow_request_${widget.requesterUid}';
      await ref.read(notificationServiceProvider).deleteNotification(
            widget.currentUid,
            deterministicNotificationId,
          );

      if (mounted) setState(() => _success = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.failedWithError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Text(context.t.notifProcessed,
          style: TextStyle(color: context.textSecondary, fontSize: 12));
    }
    if (_busy) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _busy ? null : _reject,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE04E5C)),
            ),
            child: Text(
              context.t.notifReject,
              style: const TextStyle(
                  color: Color(0xFFE04E5C),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: _busy ? null : _accept,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFB44FFF),
            ),
            child: Text(
              context.t.notifAccept,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
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
      future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
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
            errorWidget: (_, __, ___) => const SizedBox(width: 45, height: 45),
          ),
        );
      },
    );
  }
}
