import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/model/story_comment_model.dart';
import '../features/widgets/story_text_overlay.dart';
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

  /// When this story was created by sharing a feed post, holds that
  /// post's id. The viewer then renders the post as a card and tapping
  /// it opens the original post. Null for normal photo stories.
  final String? sharedPostId;

  /// Optional video for video stories. When set, the viewer plays the
  /// video instead of rendering [imageUrl]. [imageUrl] may still hold a
  /// thumbnail used in the inbox previews.
  final String? videoUrl;

  /// Optional pure-text story content. When set, the viewer renders
  /// [textContent] on a solid background ([backgroundColor]) instead of
  /// loading an image — used when the user composes a text-only story.
  final String? textContent;
  final int? backgroundColor;
  final int? textColor;

  /// Optional shape wrapping the text — one of: 'none', 'rounded',
  /// 'box', 'outline', 'pill', 'brush'. Defaults to 'none'. Stored as a
  /// string so we don't have to migrate the Firestore docs when adding
  /// new shapes.
  final String? textBorderStyle;

  /// Free-form text overlays placed on top of the media (image or
  /// video). For image stories the overlays are also burned into the
  /// uploaded composite, but we keep the structured list so the viewer
  /// can re-render them crisply at any size. For video stories the
  /// overlays are the ONLY source of truth since we can't bake them
  /// into the video bytes from Flutter.
  final List<StoryTextOverlay> overlays;

  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get isText =>
      (textContent != null && textContent!.trim().isNotEmpty) &&
      imageUrl.isEmpty &&
      !isVideo &&
      (sharedPostId == null || sharedPostId!.isEmpty);

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
    this.sharedPostId,
    this.videoUrl,
    this.textContent,
    this.backgroundColor,
    this.textColor,
    this.textBorderStyle,
    this.overlays = const [],
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
      sharedPostId: (d['sharedPostId'] as String?)?.trim(),
      videoUrl: (d['videoUrl'] as String?)?.trim(),
      textContent: (d['textContent'] as String?),
      backgroundColor: (d['backgroundColor'] as num?)?.toInt(),
      textColor: (d['textColor'] as num?)?.toInt(),
      textBorderStyle: (d['textBorderStyle'] as String?)?.trim(),
      overlays: ((d['overlays'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StoryTextOverlay.fromJson)
          .toList(growable: false),
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

  /// Creates a story. A story can be one of three kinds:
  ///   • Image — pass [imageUrl] (optionally [sharedPostId]).
  ///   • Video — pass [videoUrl] (and an optional [imageUrl] thumbnail).
  ///   • Text-only — pass [textContent] with [backgroundColor]/[textColor];
  ///     [imageUrl] may be left empty.
  Future<String> createStory({
    required String imageUrl,
    String? sharedPostId,
    String? videoUrl,
    String? textContent,
    int? backgroundColor,
    int? textColor,
    String? textBorderStyle,
    List<StoryTextOverlay> overlays = const [],
  }) async {
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
      if (sharedPostId != null && sharedPostId.isNotEmpty)
        'sharedPostId': sharedPostId,
      if (videoUrl != null && videoUrl.isNotEmpty) 'videoUrl': videoUrl,
      if (textContent != null && textContent.trim().isNotEmpty)
        'textContent': textContent,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (textColor != null) 'textColor': textColor,
      if (textBorderStyle != null && textBorderStyle.isNotEmpty)
        'textBorderStyle': textBorderStyle,
      if (overlays.isNotEmpty)
        'overlays': overlays.map((o) => o.toJson()).toList(),
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

  /// Live count of users who liked the story. Used by the story viewer to
  /// render the "Y likes" pill next to the views pill (story-owner view).
  Stream<int> streamLikesCount(String storyId) {
    return _col
        .doc(storyId)
        .collection('likes')
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Live list of users who liked the story, newest first. Used by the
  /// likes bottom sheet shown when the story owner taps the likes pill.
  Stream<List<StoryViewer>> streamLikers(String storyId) {
    return _col
        .doc(storyId)
        .collection('likes')
        .snapshots()
        .asyncMap((snap) async {
      // The likes subcollection only stores {createdAt}. Hydrate each entry
      // with the corresponding user doc so we can render avatar/username.
      final entries = await Future.wait(snap.docs.map((d) async {
        final userSnap = await _db.collection('users').doc(d.id).get();
        final u = userSnap.data() ?? {};
        return StoryViewer(
          uid: d.id,
          username: (u['username'] as String?) ?? '',
          avatarUrl: u['avatarUrl'] as String?,
          viewedAt: (d.data()['createdAt'] as Timestamp?)?.toDate(),
        );
      }));
      entries.sort((a, b) {
        final av = a.viewedAt;
        final bv = b.viewedAt;
        if (av == null) return 1;
        if (bv == null) return -1;
        return bv.compareTo(av);
      });
      return entries;
    });
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
