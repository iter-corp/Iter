import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class AppNotification {
  final String id;
  final String type;
  final String actorUid;
  final String? targetId;
  final String? commentId;
  final bool read;
  final String? status;
  final DateTime? createdAt;
  final String? title;
  final String? subtitle;

  const AppNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    this.targetId,
    this.commentId,
    required this.read,
    this.status,
    this.createdAt,
    this.title,
    this.subtitle,
  });

  factory AppNotification.fromJson(Map<String, dynamic> d) {
    DateTime? createdAt;
    final raw = d['createdAt'];
    if (raw is String) createdAt = DateTime.tryParse(raw);
    if (raw is int) createdAt = DateTime.fromMillisecondsSinceEpoch(raw);

    return AppNotification(
      id: (d['id'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'unknown',
      actorUid: (d['actorUid'] as String?) ?? '',
      targetId: d['targetId'] as String?,
      commentId: d['commentId'] as String?,
      read: d['read'] == true,
      status: d['status'] as String?,
      createdAt: createdAt,
      title: d['title'] as String?,
      subtitle: d['subtitle'] as String?,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final StreamController<List<AppNotification>> _notifsController =
      StreamController<List<AppNotification>>.broadcast();
  final StreamController<int> _unreadController =
      StreamController<int>.broadcast();

  Stream<List<AppNotification>> getNotifications(String uid) {
    refreshNotifications();
    return _notifsController.stream;
  }

  Stream<int> getUnreadCount(String uid) {
    refreshUnreadCount();
    return _unreadController.stream;
  }

  Future<void> refreshNotifications() async {
    try {
      final res = await ApiClient.instance.get('/notifications');
      if (res is List) {
        final list = res
            .whereType<Map<String, dynamic>>()
            .map(AppNotification.fromJson)
            .toList();
        _notifsController.add(list);
      }
    } catch (e) {
      debugPrint('[NotificationService] refreshNotifications error: $e');
    }
  }

  Future<void> refreshUnreadCount() async {
    try {
      final res = await ApiClient.instance.get('/notifications/unread-count');
      if (res is Map<String, dynamic> && res.containsKey('count')) {
        final count = (res['count'] as num).toInt();
        _unreadController.add(count);
      }
    } catch (_) {}
  }

  Future<void> markRead(String uid, String notifId) async {
    await ApiClient.instance.post('/notifications/$notifId/read');
    refreshNotifications();
    refreshUnreadCount();
  }

  Future<void> markNotificationsRead(String uid, Iterable<String> ids) async {
    for (final id in ids) {
      try {
        await ApiClient.instance.post('/notifications/$id/read');
      } catch (_) {}
    }
    refreshNotifications();
    refreshUnreadCount();
  }

  Future<void> markUnread(String uid, String notifId) async {}

  Future<void> updateNotificationStatus(String uid, String notifId, String status) async {
    await markRead(uid, notifId);
  }

  Future<void> markAllRead(String uid) async {
    await ApiClient.instance.post('/notifications/read-all');
    refreshNotifications();
    refreshUnreadCount();
  }

  Future<void> createNotification({
    required String targetUid,
    required String type,
    required String actorUid,
    String? targetId,
    String? commentId,
  }) async {}

  Future<void> sendMentionNotifications({
    required List<String> targetUids,
    required String actorUid,
    String? targetId,
    String? commentId,
  }) async {}

  Future<void> createSystemNotification({
    required String targetUid,
    required String type,
    required String title,
    String? subtitle,
    String? targetId,
  }) async {}

  Future<void> upsertNotification({
    required String targetUid,
    required String docId,
    required String type,
    required String actorUid,
    String? targetId,
    String? commentId,
  }) async {}

  Future<void> removeNotificationById(String targetUid, String docId) async {}

  Future<void> deleteNotification(String uid, String notifId) async {}
}
