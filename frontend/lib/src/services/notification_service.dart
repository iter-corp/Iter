import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

/// Notification types written by Cloud Functions or client-side logic.
/// type values: 'follow', 'like', 'comment', 'comment_like', 'reply',
/// 'qa_answer', 'qa_reply', 'qa_answer_like', 'qa_answer_dislike',
/// 'story_like', 'story_comment', 'story_reply', 'new_event'
class AppNotification {
  final String id;
  final String type;
  final String actorUid;
  final String? targetId; // postId for like / comment, eventId for new_event
  final String? commentId; // for comment_like: the specific comment id
  final bool read;
  final String? status; // 'accepted', 'rejected', etc.
  final DateTime? createdAt;

  /// Free-text title carried on the notification doc itself. Used by
  /// system-generated notifications that have no actor user (e.g. `new_event`
  /// stores the event title here).
  final String? title;

  /// Optional subtitle (e.g. the event's location for `new_event`).
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

  factory AppNotification.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return AppNotification(
      id: doc.id,
      type: (d['type'] as String?) ?? 'unknown',
      actorUid: (d['actorUid'] as String?) ?? '',
      targetId: d['targetId'] as String?,
      commentId: d['commentId'] as String?,
      read: (d['read'] as bool?) ?? false,
      status: d['status'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      title: d['title'] as String?,
      subtitle: d['subtitle'] as String?,
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

  /// Update the status of a notification (e.g. 'accepted', 'rejected')
  Future<void> updateNotificationStatus(
          String uid, String notifId, String status) =>
      _items(uid).doc(notifId).update({
        'status': status,
        'read': true, // Auto-mark as read when taking action
      });

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

  /// Writes a system notification that doesn't belong to a specific actor
  /// user. Used for event/news style updates that should still appear in the
  /// Notifications screen with custom copy.
  Future<void> createSystemNotification({
    required String targetUid,
    required String type,
    required String title,
    String? subtitle,
    String? targetId,
  }) async {
    await _items(targetUid).add({
      'type': type,
      'actorUid': '',
      if (targetId != null) 'targetId': targetId,
      'title': title,
      if (subtitle != null && subtitle.trim().isNotEmpty)
        'subtitle': subtitle.trim(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Upserts a notification using a deterministic document ID so repeated
  /// identical actions (e.g. like → unlike → like) never create duplicates.
  /// The [docId] must be globally unique per actor+type+target combination.
  Future<void> upsertNotification({
    required String targetUid,
    required String docId,
    required String type,
    required String actorUid,
    String? targetId,
    String? commentId,
  }) async {
    await _items(targetUid).doc(docId).set({
      'type': type,
      'actorUid': actorUid,
      if (targetId != null) 'targetId': targetId,
      if (commentId != null) 'commentId': commentId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the notification with [docId] for [targetUid].
  /// Used to clean up like notifications on unlike.
  Future<void> removeNotificationById(String targetUid, String docId) =>
      _items(targetUid).doc(docId).delete();

  /// Delete a single notification.
  Future<void> deleteNotification(String uid, String notifId) =>
      _items(uid).doc(notifId).delete();
}
