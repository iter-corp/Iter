import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

/// Notification types written by Cloud Functions or client-side logic.
/// type values: 'follow', 'like', 'comment'
class AppNotification {
  final String id;
  final String type;
  final String actorUid;
  final String? targetId; // postId for like / comment notifications
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    this.targetId,
    required this.read,
    this.createdAt,
  });

  factory AppNotification.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return AppNotification(
      id: doc.id,
      type: (d['type'] as String?) ?? 'unknown',
      actorUid: (d['actorUid'] as String?) ?? '',
      targetId: d['targetId'] as String?,
      read: (d['read'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  /// Live stream of the 50 most recent notifications for [uid].
  Stream<List<AppNotification>> getNotifications(String uid) => _items(uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());

  /// Live unread count.
  Stream<int> getUnreadCount(String uid) => _items(uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);

  /// Mark a single notification as read.
  Future<void> markRead(String uid, String notifId) =>
      _items(uid).doc(notifId).update({'read': true});

  /// Mark every unread notification as read in a single batch.
  Future<void> markAllRead(String uid) async {
    final batch = _db.batch();
    final snap = await _items(uid).where('read', isEqualTo: false).get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Write a notification document. Used by the client for follow events
  /// until Cloud Functions are deployed.
  Future<void> createNotification({
    required String targetUid,
    required String type,
    required String actorUid,
    String? targetId,
  }) async {
    await _items(targetUid).add({
      'type': type,
      'actorUid': actorUid,
      if (targetId != null) 'targetId': targetId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a single notification.
  Future<void> deleteNotification(String uid, String notifId) =>
      _items(uid).doc(notifId).delete();
}
