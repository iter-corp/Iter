import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notifications = NotificationService();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _followersCol(String uid) =>
      _userDoc(uid).collection('followers');

  CollectionReference<Map<String, dynamic>> _followingCol(String uid) =>
      _userDoc(uid).collection('following');

  Future<void> follow({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    final now = FieldValue.serverTimestamp();
    final followingRef = _followingCol(currentUid).doc(targetUid);
    final followerRef = _followersCol(targetUid).doc(currentUid);

    final batch = _db.batch();
    batch.set(followingRef, {'uid': targetUid, 'createdAt': now});
    batch.set(followerRef, {'uid': currentUid, 'createdAt': now});
    await batch.commit();

    // Best-effort in-app notification write; follow should still succeed
    // even if this secondary write fails.
    try {
      await _notifications.createNotification(
        targetUid: targetUid,
        type: 'follow',
        actorUid: currentUid,
      );
    } catch (_) {}
  }

  Future<void> unfollow({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    final followingRef = _followingCol(currentUid).doc(targetUid);
    final followerRef = _followersCol(targetUid).doc(currentUid);

    final batch = _db.batch();
    batch.delete(followingRef);
    batch.delete(followerRef);
    await batch.commit();
  }

  Stream<bool> isFollowing({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return _followingCol(currentUid)
        .doc(targetUid)
        .snapshots()
        .map((s) => s.exists);
  }

  Stream<List<String>> getFollowers(String uid) {
    return _followersCol(uid).snapshots().map((snap) {
      final docs = [...snap.docs]..sort((a, b) {
          final aCreatedAt = (a.data()['createdAt'] as Timestamp?)?.toDate();
          final bCreatedAt = (b.data()['createdAt'] as Timestamp?)?.toDate();

          if (aCreatedAt == null && bCreatedAt == null) return 0;
          if (aCreatedAt == null) return 1;
          if (bCreatedAt == null) return -1;
          return bCreatedAt.compareTo(aCreatedAt);
        });

      return docs.map((doc) => doc.id).toList();
    });
  }

  Stream<List<String>> getFollowing(String uid) {
    return _followingCol(uid).snapshots().map((snap) {
      final docs = [...snap.docs]..sort((a, b) {
          final aCreatedAt = (a.data()['createdAt'] as Timestamp?)?.toDate();
          final bCreatedAt = (b.data()['createdAt'] as Timestamp?)?.toDate();

          if (aCreatedAt == null && bCreatedAt == null) return 0;
          if (aCreatedAt == null) return 1;
          if (bCreatedAt == null) return -1;
          return bCreatedAt.compareTo(aCreatedAt);
        });

      return docs.map((doc) => doc.id).toList();
    });
  }
}
