import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

class BlockService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Block a user. Stores it directly in the user document's blockedUsers array
  /// to bypass subcollection rule restrictions. Also removes all follow relationships.
  Future<void> blockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    final batch = _db.batch();

    // Add to my blockedUsers array
    batch.update(_userDoc(currentUid), {
      'blockedUsers': FieldValue.arrayUnion([targetUid]),
    });

    // Clean up all follow relationships:
    // 1. I unfollow them
    final myFollowingRef = _userDoc(currentUid).collection('following').doc(targetUid);
    batch.delete(myFollowingRef);

    // 2. I remove myself from their followers
    final theirFollowerRef = _userDoc(targetUid).collection('followers').doc(currentUid);
    batch.delete(theirFollowerRef);

    // 3. They unfollow me (remove them from my followers)
    final theirFollowingRef = _userDoc(targetUid).collection('following').doc(currentUid);
    batch.delete(theirFollowingRef);

    // 4. Remove them from my followers
    final myFollowerRef = _userDoc(currentUid).collection('followers').doc(targetUid);
    batch.delete(myFollowerRef);

    await batch.commit();
  }

  /// Unblock a user.
  Future<void> unblockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;
    await _userDoc(currentUid).update({
      'blockedUsers': FieldValue.arrayRemove([targetUid]),
    });
  }

  /// Stream whether [currentUid] has blocked [targetUid].
  Stream<bool> isBlocked({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return _userDoc(currentUid).snapshots().map((s) {
      final data = s.data();
      if (data == null) return false;
      final blocked = List<String>.from(data['blockedUsers'] ?? []);
      return blocked.contains(targetUid);
    }).onErrorReturn(false);
  }

  /// Stream whether [targetUid] has blocked [currentUid].
  Stream<bool> isBlockedBy({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return _userDoc(targetUid).snapshots().map((s) {
      final data = s.data();
      if (data == null) return false;
      final blocked = List<String>.from(data['blockedUsers'] ?? []);
      return blocked.contains(currentUid);
    }).onErrorReturn(false);
  }

  /// Stream the list of UIDs that [uid] has blocked.
  Stream<List<String>> getBlockedUsers(String uid) {
    return _userDoc(uid).snapshots().map((s) {
      final data = s.data();
      if (data == null) return <String>[];
      return List<String>.from(data['blockedUsers'] ?? []);
    }).onErrorReturn(<String>[]);
  }
}
