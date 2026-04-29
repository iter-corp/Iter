import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tracks "who viewed my profile" in a flat subcollection at
/// `users/{ownerUid}/visitors/{visitorUid}`. We store one doc per
/// visitor and refresh the timestamp on each subsequent visit so the
/// owner sees a deduped, recency-sorted list. The visitor's own profile
/// view never gets recorded.
class ProfileVisitorEntry {
  final String uid;
  final DateTime? lastVisitedAt;
  final int visitCount;

  const ProfileVisitorEntry({
    required this.uid,
    required this.lastVisitedAt,
    required this.visitCount,
  });

  factory ProfileVisitorEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return ProfileVisitorEntry(
      uid: doc.id,
      lastVisitedAt: (d['lastVisitedAt'] as Timestamp?)?.toDate(),
      visitCount: (d['visitCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProfileVisitorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('visitors');

  /// Record that the signed-in user just viewed [ownerUid]'s profile.
  /// No-op when the viewer is the owner (we don't want a user to show
  /// up in their own visitor list) or when no one is signed in.
  Future<void> recordVisit(String ownerUid) async {
    final viewer = _auth.currentUser?.uid;
    if (viewer == null || ownerUid.isEmpty || viewer == ownerUid) return;
    try {
      await _col(ownerUid).doc(viewer).set({
        'lastVisitedAt': FieldValue.serverTimestamp(),
        'visitCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort — Firestore rules might forbid the write on accounts
      // that haven't opted in. Failing silently keeps profile views
      // working even when this side feature isn't deployed.
    }
  }

  /// Stream of visitors to [ownerUid], newest first.
  Stream<List<ProfileVisitorEntry>> streamVisitors(String ownerUid) {
    return _col(ownerUid).snapshots().map((s) {
      final list = s.docs.map(ProfileVisitorEntry.fromDoc).toList();
      list.sort((a, b) {
        final av = a.lastVisitedAt;
        final bv = b.lastVisitedAt;
        if (av == null) return 1;
        if (bv == null) return -1;
        return bv.compareTo(av);
      });
      return list;
    });
  }

  /// Live count of unique visitors for [ownerUid].
  Stream<int> streamVisitorCount(String ownerUid) {
    return _col(ownerUid).snapshots().map((s) => s.size);
  }
}
