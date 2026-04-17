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
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class StoryViewer {
  final String uid;
  final String username;
  final String? avatarUrl;
  final DateTime? viewedAt;

  const StoryViewer({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.viewedAt,
  });

  factory StoryViewer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StoryViewer(
      uid: doc.id,
      username: (d['username'] as String?) ?? '',
      avatarUrl: d['avatarUrl'] as String?,
      viewedAt: (d['viewedAt'] as Timestamp?)?.toDate(),
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
    return _col.where('expiresAt', isGreaterThan: now).snapshots().map((s) {
      final stories = s.docs.map(Story.fromDoc).toList();
      stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return stories;
    });
  }

  Future<void> deleteStory(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    await _col.doc(storyId).delete();
  }

  Future<void> recordView(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final storySnap = await _col.doc(storyId).get();
    final authorUid = storySnap.data()?['authorUid'] as String?;
    if (authorUid == null || authorUid == user.uid) return;

    final viewerRef = _col.doc(storyId).collection('viewers').doc(user.uid);
    final existing = await viewerRef.get();
    if (existing.exists) return;

    final userSnap = await _db.collection('users').doc(user.uid).get();
    final userData = userSnap.data() ?? {};

    await viewerRef.set({
      'username': (userData['username'] as String?) ?? '',
      'avatarUrl': userData['avatarUrl'] as String?,
      'viewedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<StoryViewer>> streamViewers(String storyId) {
    return _col.doc(storyId).collection('viewers').snapshots().map((s) {
      final viewers = s.docs.map(StoryViewer.fromDoc).toList();
      viewers.sort((a, b) {
        final av = a.viewedAt;
        final bv = b.viewedAt;
        if (av == null) return 1;
        if (bv == null) return -1;
        return bv.compareTo(av);
      });
      return viewers;
    });
  }
}
