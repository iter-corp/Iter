import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Story {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String imageUrl;
  final DateTime createdAt;
  final DateTime expiresAt;

  const Story({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Story.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Story(
      id: doc.id,
      authorUid: (d['authorUid'] as String?) ?? '',
      authorUsername: (d['authorUsername'] as String?) ?? '',
      authorAvatar: d['authorAvatar'] as String?,
      imageUrl: (d['imageUrl'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (d['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class StoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('stories');

  Future<String> createStory({required String imageUrl}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final userSnap = await _db.collection('users').doc(user.uid).get();
    final userData = userSnap.data() ?? {};
    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 24));

    final ref = await _col.add({
      'authorUid': user.uid,
      'authorUsername': (userData['username'] as String?) ?? '',
      'authorAvatar': userData['avatarUrl'] as String?,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
    });
    return ref.id;
  }

  Stream<List<Story>> streamActiveStories() {
    final now = Timestamp.fromDate(DateTime.now());
    return _col
        .where('expiresAt', isGreaterThan: now)
        .snapshots()
        .map((s) {
      final stories = s.docs.map(Story.fromDoc).toList();
      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return stories;
    });
  }
}
