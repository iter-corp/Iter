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

  Future<bool> isUsernameTaken(String username) async {
    final q = await _db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }
}
