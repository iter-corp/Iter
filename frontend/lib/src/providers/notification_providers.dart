import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import 'auth_providers.dart';

final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());

/// Live stream of the current user's notifications.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationServiceProvider).getNotifications(user.uid);
});

/// Live count of unread notifications — drives the bell badge.
final unreadCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(0);
  return ref.watch(notificationServiceProvider).getUnreadCount(user.uid);
});
