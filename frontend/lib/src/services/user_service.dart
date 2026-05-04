import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final snap = await _doc(uid).get();
    return snap.data();
  }

  Stream<Map<String, dynamic>?> streamUser(String uid) =>
      _doc(uid).snapshots().map((s) => s.data());

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      _doc(uid).set(data, SetOptions(merge: true));

  String normalizeUsername(String username) => username.trim().toLowerCase();

  Future<bool> isUsernameTaken(
    String username, {
    String? excludeUid,
  }) async {
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return false;

    bool _containsOtherUid(QuerySnapshot<Map<String, dynamic>> snap) {
      return snap.docs.any((d) => excludeUid == null || d.id != excludeUid);
    }

    // Fast path for current schema.
    final byLower = await _db
        .collection('users')
        .where('usernameLower', isEqualTo: normalized)
        .limit(5)
        .get();
    if (_containsOtherUid(byLower)) return true;

    // Compatibility for docs that may only have lowercase username.
    final byExact = await _db
        .collection('users')
        .where('username', isEqualTo: normalized)
        .limit(5)
        .get();
    if (_containsOtherUid(byExact)) return true;

    // Legacy fallback: compare case-insensitively for older docs where
    // usernameLower may be missing and username had mixed casing.
    final allUsers = await _db.collection('users').get();
    for (final doc in allUsers.docs) {
      if (excludeUid != null && doc.id == excludeUid) continue;
      final existing = (doc.data()['username'] as String?) ?? '';
      if (normalizeUsername(existing) == normalized) return true;
    }
    return false;
  }
}
