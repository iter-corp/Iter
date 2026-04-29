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

  /// Deterministic notification doc id for a follow event between two
  /// users. Guarantees a single notification doc per (actor, target)
  /// pair so we don't pile up duplicates when the user follows /
  /// unfollows / refollows.
  String _followNotifId(String actorUid) => 'follow_$actorUid';

  Future<void> follow({
    required String currentUid,
    required String targetUid,
    required bool isPrivate,
  }) async {
    if (currentUid == targetUid) return;

    final now = FieldValue.serverTimestamp();
    final status = isPrivate ? 'pending' : 'active';

    final followingRef = _followingCol(currentUid).doc(targetUid);
    final followerRef = _followersCol(targetUid).doc(currentUid);

    final batch = _db.batch();
    batch.set(followingRef, {'uid': targetUid, 'createdAt': now, 'status': status});
    batch.set(followerRef, {'uid': currentUid, 'createdAt': now, 'status': status});
    await batch.commit();

    if (!isPrivate) {
      try {
        // upsert by deterministic id so a follow → unfollow → follow
        // cycle doesn't pile up notification rows. The unfollow path
        // below also removes this id, so the badge clears when the
        // relationship goes away.
        await _notifications.upsertNotification(
          targetUid: targetUid,
          docId: _followNotifId(currentUid),
          type: 'follow',
          actorUid: currentUid,
        );
      } catch (_) {}
    }
    // Note: For pending follow_requests (when isPrivate=true), the backend's
    // onFollowCreate trigger already creates the notification with a deterministic ID.
    // Do not create a duplicate notification on the client.
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

    // Clear the matching follow notification on the target's side so
    // the receiver doesn't see a stale entry pointing at a follow that
    // no longer exists. Best-effort — security rules might forbid us
    // from touching the target's notifications subcollection on some
    // configs, in which case the entry stays put until next visit.
    try {
      await _notifications.removeNotificationById(
        targetUid,
        _followNotifId(currentUid),
      );
    } catch (_) {}
  }

  Future<void> acceptFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    // 1. Get the pending follow request
    final followerRef = _followersCol(currentUid).doc(requesterUid);
    final followerSnap = await followerRef.get();

    if (!followerSnap.exists) {
      throw Exception('Follow request not found at path: users/$currentUid/followers/$requesterUid');
    }

    // 2. Verify the following document reference
    final followingRef = _followingCol(requesterUid).doc(currentUid);

    // 3. Update both documents to 'active' using set(merge: true).
    // Using set(merge: true) is more robust than update() because it succeeds
    // even if the document was temporarily deleted or desynced, avoiding 
    // PERMISSION_DENIED errors on non-existent documents.
    final batch = _db.batch();

    batch.set(followerRef, {
      'status': 'active',
      'acceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(followingRef, {
      'status': 'active',
      'acceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 4. Create an 'accept' notification for the requester
    final notificationRef = _db
        .collection('notifications')
        .doc(requesterUid)
        .collection('items')
        .doc();
    batch.set(notificationRef, {
      'type': 'follow_accept',
      'actorUid': currentUid,
      'targetId': currentUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to accept follow request. Error: $e. Make sure you are authenticated as the account receiving the follow request (currentUid: $currentUid)');
    }
  }

  Future<void> rejectFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    // Verify the follow request documents exist before attempting to delete them
    final followerRef = _followersCol(currentUid).doc(requesterUid);
    final followerSnap = await followerRef.get();

    if (!followerSnap.exists) {
      throw Exception('Follow request not found at path: users/$currentUid/followers/$requesterUid');
    }

    // Delete both documents in an atomic batch
    // Rules allow delete if: isSelf(followerUid) || isSelf(uid) || isAdmin()
    // Which means: the requester can delete, the target can delete, or admin can delete
    try {
      await unfollow(currentUid: requesterUid, targetUid: currentUid);
    } catch (e) {
      throw Exception('Failed to reject follow request. Error: $e. Make sure you are authenticated as the account receiving the follow request (currentUid: $currentUid)');
    }
  }

  Stream<bool> isFollowing({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return _followingCol(currentUid)
        .doc(targetUid)
        .snapshots()
        .map((s) => s.exists && s.data()?['status'] != 'pending');
  }

  Stream<bool> hasRequestedFollow({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return _followingCol(currentUid)
        .doc(targetUid)
        .snapshots()
        .map((s) => s.exists && s.data()?['status'] == 'pending');
  }

  Stream<List<String>> getFollowers(String uid) {
    return _followersCol(uid).snapshots().map((snap) {
      final activeDocs = snap.docs.where((d) => d.data()['status'] != 'pending').toList();
      activeDocs.sort((a, b) {
        final aCreatedAt = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bCreatedAt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (aCreatedAt == null && bCreatedAt == null) return 0;
        if (aCreatedAt == null) return 1;
        if (bCreatedAt == null) return -1;
        return bCreatedAt.compareTo(aCreatedAt);
      });
      return activeDocs.map((doc) => doc.id).toList();
    });
  }

  Stream<List<String>> getFollowRequests(String uid) {
    return _followersCol(uid).snapshots().map((snap) {
      final pendingDocs = snap.docs.where((d) => d.data()['status'] == 'pending').toList();
      pendingDocs.sort((a, b) {
        final aCreatedAt = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bCreatedAt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (aCreatedAt == null && bCreatedAt == null) return 0;
        if (aCreatedAt == null) return 1;
        if (bCreatedAt == null) return -1;
        return bCreatedAt.compareTo(aCreatedAt);
      });
      return pendingDocs.map((doc) => doc.id).toList();
    });
  }

  Stream<List<String>> getFollowing(String uid) {
    return _followingCol(uid).snapshots().map((snap) {
      final activeDocs = snap.docs.where((d) => d.data()['status'] != 'pending').toList();
      activeDocs.sort((a, b) {
        final aCreatedAt = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bCreatedAt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (aCreatedAt == null && bCreatedAt == null) return 0;
        if (aCreatedAt == null) return 1;
        if (bCreatedAt == null) return -1;
        return bCreatedAt.compareTo(aCreatedAt);
      });
      return activeDocs.map((doc) => doc.id).toList();
    });
  }
}
