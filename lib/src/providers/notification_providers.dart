import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'follow_providers.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import 'auth_providers.dart';

final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());

/// The current user's new-event notification preferences.
final eventNotifPrefsProvider = StreamProvider<EventNotifPrefs>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(userServiceProvider).streamEventNotifPrefs(user.uid);
});

/// Live stream of the current user's notifications.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationServiceProvider).getNotifications(user.uid);
});

/// Live count of unread notifications for the bell badge.
///
/// Includes persisted unread notification docs and pending follow requests
/// that can appear as synthetic items in NotificationScreen.
final unreadCountProvider = Provider<int>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return 0;

  final notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
  final followRequests =
      ref.watch(followRequestsProvider(user.uid)).valueOrNull ??
          const <String>[];

  final persistedRequestActors = notifications
      .where((n) => n.type == 'follow_request')
      .map((n) => n.actorUid)
      .toSet();

  final unreadPersisted = notifications.where((n) => !n.read).length;
  final unreadSyntheticRequests = followRequests
      .where((uid) => !persistedRequestActors.contains(uid))
      .length;

  return unreadPersisted + unreadSyntheticRequests;
});
