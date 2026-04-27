import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/model/story_comment_model.dart';
import 'notification_service.dart';


class Story {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String imageUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int likesCount;
  final int commentsCount;

  const Story({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
    this.likesCount = 0,
    this.commentsCount = 0,
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
      likesCount: (d['likesCount'] as int?) ?? 0,
      commentsCount: (d['commentsCount'] as int?) ?? 0,
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
  final NotificationService _notifications = NotificationService();

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
      // Oldest first so new stories play last (Instagram-style).
      stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return stories;
    });
  }

  /// Checks whether the current user has viewed a specific story.
  Future<bool> hasViewed(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc =
        await _col.doc(storyId).collection('viewers').doc(user.uid).get();
    return doc.exists;
  }

  Future<void> deleteStory(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    await _col.doc(storyId).delete();
  }

  Future<void> recordView(String storyId, {required String authorUid}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (authorUid.isEmpty || authorUid == user.uid) return;

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
    return _col
        .doc(storyId)
        .collection('viewers')
        .snapshots()
        .map((s) {
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

  Future<void> toggleLike(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final likeRef = _col.doc(storyId).collection('likes').doc(user.uid);
    final storyRef = _col.doc(storyId);
    bool didLike = false;
    String? authorUid;

    await _db.runTransaction((tx) async {
      final storySnap = await tx.get(storyRef);
      authorUid = storySnap.data()?['authorUid'] as String?;

      final likeSnap = await tx.get(likeRef);
      if (likeSnap.exists) {
        didLike = false;
        tx.delete(likeRef);
        tx.update(storyRef, {'likesCount': FieldValue.increment(-1)});
      } else {
        didLike = true;
        tx.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
        tx.update(storyRef, {'likesCount': FieldValue.increment(1)});
      }
    });

    // Notification for story like
    if (authorUid != null && authorUid != user.uid) {
      final notifId = 'story_like_${user.uid}_$storyId';
      try {
        if (didLike) {
          await _notifications.upsertNotification(
            targetUid: authorUid!,
            docId: notifId,
            type: 'story_like',
            actorUid: user.uid,
            targetId: storyId,
          );
        } else {
          await _notifications.removeNotificationById(authorUid!, notifId);
        }
      } catch (_) {}
    }
  }

  Stream<bool> streamIsLiked(String storyId, {String? uid}) {
    final effectiveUid = uid ?? _auth.currentUser?.uid;
    if (effectiveUid == null) return Stream.value(false);
    return _col
        .doc(storyId)
        .collection('likes')
        .doc(effectiveUid)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> addComment({
    required String storyId,
    required String authorUid,
    required String authorUsername,
    String? authorAvatar,
    required String text,
    String? parentCommentId,
    String? replyToUsername,
  }) async {
    final commentRef = _col.doc(storyId).collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      if (replyToUsername != null) 'replyToUsername': replyToUsername,
    });
    batch.update(_col.doc(storyId), {
      'commentsCount': FieldValue.increment(1),
    });
    await batch.commit();

    // Notification for story comment
    if (parentCommentId != null) {
      try {
        final parentSnap =
            await _col.doc(storyId).collection('comments').doc(parentCommentId).get();
        final parentAuthorUid =
            parentSnap.data()?['authorUid'] as String?;
        if (parentAuthorUid != null && parentAuthorUid != authorUid) {
          await _notifications.createNotification(
            targetUid: parentAuthorUid,
            type: 'story_reply',
            actorUid: authorUid,
            targetId: storyId,
          );
        }
      } catch (_) {}
    } else {
      // Notification for story comment to story author
      final storySnap = await _col.doc(storyId).get();
      final storyAuthorUid = storySnap.data()?['authorUid'] as String?;
      if (storyAuthorUid != null && storyAuthorUid != authorUid) {
        await _notifications.createNotification(
          targetUid: storyAuthorUid,
          type: 'story_comment',
          actorUid: authorUid,
          targetId: storyId,
        );
      }
    }
  }

  Stream<List<StoryComment>> streamComments(String storyId) {
    return _col
        .doc(storyId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(StoryComment.fromDoc).toList());
  }

  Future<void> deleteComment({
    required String storyId,
    required String commentId,
  }) async {
    final batch = _db.batch();
    batch.delete(_col.doc(storyId).collection('comments').doc(commentId));
    batch.update(_col.doc(storyId), {
      'commentsCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }
} 
