import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/model/post_model.dart';

class PostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  Future<String> createPost({
    required String caption,
    List<String> imageUrls = const [],
    bool isPrivate = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] as String? ?? 'user';
    final avatar = userDoc.data()?['avatarUrl'] as String?;

    final ref = await _posts.add({
      'authorUid': user.uid,
      'authorUsername': username,
      'authorAvatar': avatar,
      'caption': caption,
      'imageUrls': imageUrls,
      'likesCount': 0,
      'commentsCount': 0,
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(user.uid).update({
      'postsCount': FieldValue.increment(1),
    });

    return ref.id;
  }

  Stream<List<Post>> streamFeed({int limit = 50}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  Stream<List<Post>> streamUserPosts(String uid) {
    return _posts
        .where('authorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  Future<void> deletePost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    await _posts.doc(postId).delete();
    await _db.collection('users').doc(uid).update({
      'postsCount': FieldValue.increment(-1),
    });
  }

  Future<void> toggleLike(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final likeRef = _posts.doc(postId).collection('likes').doc(user.uid);
    final postRef = _posts.doc(postId);

    await _db.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      if (likeSnap.exists) {
        tx.delete(likeRef);
        tx.update(postRef, {'likesCount': FieldValue.increment(-1)});
      } else {
        tx.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
        tx.update(postRef, {'likesCount': FieldValue.increment(1)});
      }
    });
  }

  Stream<bool> streamIsLiked(String postId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _posts
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((s) => s.exists);
  }
}
