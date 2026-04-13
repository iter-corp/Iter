import 'package:cloud_firestore/cloud_firestore.dart';

class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

    await _db.runTransaction((tx) async {
      final followingRef = _followingCol(currentUid).doc(targetUid);
      final followerRef = _followersCol(targetUid).doc(currentUid);

      final alreadyFollowing = await tx.get(followingRef);
      if (alreadyFollowing.exists) return;

      tx.set(followingRef, {'uid': targetUid, 'createdAt': now});
      tx.set(followerRef, {'uid': currentUid, 'createdAt': now});
    });
  }

  Future<void> unfollow({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    await _db.runTransaction((tx) async {
      final followingRef = _followingCol(currentUid).doc(targetUid);
      final followerRef = _followersCol(targetUid).doc(currentUid);

      final existing = await tx.get(followingRef);
      if (!existing.exists) return;

      tx.delete(followingRef);
      tx.delete(followerRef);
    });
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
    return _followersCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  Stream<List<String>> getFollowing(String uid) {
    return _followingCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }
}
