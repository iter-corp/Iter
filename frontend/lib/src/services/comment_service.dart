import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'profanity_filter_service.dart';

/// Thrown by [CommentService.editComment] when the new text would
/// introduce profanity into a comment that was previously clean.
/// Callers should treat this as a user-fixable error (show a snackbar
/// telling the author the edit was rejected) — not a service crash.
class ProfanityEditRejected implements Exception {
  const ProfanityEditRejected();
  @override
  String toString() => 'ProfanityEditRejected';
}

class Comment {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToUsername;
  final int helpfulCount;
  final int unhelpfulCount;
  final bool profanityFiltered;
  final bool senderOnly;

  const Comment({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    this.authorAvatar,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
    this.replyToUsername,
    this.helpfulCount = 0,
    this.unhelpfulCount = 0,
    this.profanityFiltered = false,
    this.senderOnly = false,
  });

  bool get isReply => parentCommentId != null;

  factory Comment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Comment(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorUsername: d['authorUsername'] as String? ?? 'unknown',
      authorAvatar: d['authorAvatar'] as String?,
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      parentCommentId: d['parentCommentId'] as String?,
      replyToUsername: d['replyToUsername'] as String?,
      helpfulCount: (d['helpfulCount'] as num?)?.toInt() ?? 0,
      unhelpfulCount: (d['unhelpfulCount'] as num?)?.toInt() ?? 0,
      profanityFiltered: d['profanityFiltered'] == true,
      senderOnly: d['senderOnly'] == true,
    );
  }
}

class CommentService {
  final _db = FirebaseFirestore.instance;
  final NotificationService _notifications = NotificationService();
  final ProfanityFilterService _profanityFilter = ProfanityFilterService();

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  CollectionReference<Map<String, dynamic>> _privateComments(
    String postId,
    String uid,
  ) =>
      _db
          .collection('posts')
          .doc(postId)
          .collection('privateComments')
          .doc(uid)
          .collection('items');

  CollectionReference<Map<String, dynamic>> _likes(
    String postId,
    String commentId,
  ) =>
      _comments(postId).doc(commentId).collection('likes');

  DocumentReference<Map<String, dynamic>> _postRef(String postId) =>
      _db.collection('posts').doc(postId);

  CollectionReference<Map<String, dynamic>> _reactions(
    String postId,
    String commentId,
  ) =>
      _comments(postId).doc(commentId).collection('reactions');

  /// Live count of *public* comments / answers on [postId]. This is
  /// what the QA cards and the answer count badge should display —
  /// counting straight from the subcollection means the number is
  /// always in sync with reality, even on legacy posts whose cached
  /// `commentsCount` on the post doc drifted into negative territory.
  Stream<int> streamCommentsCount(String postId) {
    return _comments(postId).snapshots().map((s) => s.docs.length);
  }

  Stream<List<Comment>> streamComments(
    String postId, {
    required String viewerUid,
  }) {
    final controller = StreamController<List<Comment>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? publicSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? privateSub;
    List<Comment> publicComments = const [];
    List<Comment> privateComments = const [];

    void emitMerged() {
      final merged = [...publicComments, ...privateComments]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!controller.isClosed) controller.add(merged);
    }

    controller.onListen = () {
      publicSub = _comments(postId)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) {
        publicComments = snap.docs.map(Comment.fromDoc).toList();
        emitMerged();
      }, onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      });

      privateSub = _privateComments(postId, viewerUid)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) {
        privateComments = snap.docs.map(Comment.fromDoc).toList();
        emitMerged();
      }, onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      });
    };

    controller.onCancel = () async {
      await publicSub?.cancel();
      await privateSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorUsername,
    String? authorAvatar,
    required String text,
    String? parentCommentId,
    String? replyToUsername,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final profanityMatches = await _profanityFilter.findMatches(trimmed);
    final isProfanityFiltered = profanityMatches.isNotEmpty;

    final commentRef = isProfanityFiltered
        ? _privateComments(postId, authorUid).doc()
        : _comments(postId).doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'helpfulCount': 0,
      'unhelpfulCount': 0,
      if (isProfanityFiltered) 'profanityFiltered': true,
      if (isProfanityFiltered) 'senderOnly': true,
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      if (replyToUsername != null) 'replyToUsername': replyToUsername,
    });
    if (!isProfanityFiltered) {
      batch.update(_postRef(postId), {
        'commentsCount': FieldValue.increment(1),
      });
    }
    await batch.commit();

    if (isProfanityFiltered) {
      // Sender-only moderated comments never fan out notifications.
      return;
    }

    // Spark-safe fallback: generate notifications from the client for Q&A
    // events and replies when backend functions are unavailable.
    try {
      final postSnap = await _postRef(postId).get();
      final postData = postSnap.data() ?? {};
      final isQa = (postData['postType'] as String?) == 'qa';

      if (isQa) {
        if (parentCommentId == null) {
          final questionAuthorUid = postData['authorUid'] as String?;
          if (questionAuthorUid != null && questionAuthorUid != authorUid) {
            await _notifications.upsertNotification(
              targetUid: questionAuthorUid,
              docId: 'qa_answer_${postId}_${commentRef.id}_$authorUid',
              type: 'qa_answer',
              actorUid: authorUid,
              targetId: postId,
              commentId: commentRef.id,
            );
          }
        } else {
          final parentSnap = await _comments(postId).doc(parentCommentId).get();
          final parentAuthorUid = parentSnap.data()?['authorUid'] as String?;
          if (parentAuthorUid != null && parentAuthorUid != authorUid) {
            await _notifications.upsertNotification(
              targetUid: parentAuthorUid,
              docId: 'qa_reply_${postId}_${commentRef.id}_$authorUid',
              type: 'qa_reply',
              actorUid: authorUid,
              targetId: postId,
              commentId: commentRef.id,
            );
          }
        }
        return;
      }

      if (parentCommentId != null) {
        final parentSnap = await _comments(postId).doc(parentCommentId).get();
        final parentAuthorUid = parentSnap.data()?['authorUid'] as String?;
        if (parentAuthorUid != null && parentAuthorUid != authorUid) {
          // Pass `commentId` (the new reply's id) so tapping the
          // notification lands directly on the reply, scrolls to it,
          // and highlights it for ~3s — matching how `comment_like`
          // and the QA `qa_reply` flows already behave.
          await _notifications.createNotification(
            targetUid: parentAuthorUid,
            type: 'reply',
            actorUid: authorUid,
            targetId: postId,
            commentId: commentRef.id,
          );
        }
      } else {
        // Top-level comment on a regular (non-QA) post — notify the
        // post's author so they hear about new comments. This branch
        // was missing, which is why the post author got nothing when
        // someone commented on their post (only `like`, `comment_like`
        // and `reply` were firing).
        final postAuthorUid = postData['authorUid'] as String?;
        debugPrint('[CommentNotif] top-level non-QA comment: '
            'postAuthorUid=$postAuthorUid actorUid=$authorUid '
            'postId=$postId commentId=${commentRef.id}');
        if (postAuthorUid != null && postAuthorUid != authorUid) {
          try {
            await _notifications.createNotification(
              targetUid: postAuthorUid,
              type: 'comment',
              actorUid: authorUid,
              targetId: postId,
              commentId: commentRef.id,
            );
            debugPrint('[CommentNotif] notification written OK');
          } catch (e) {
            debugPrint('[CommentNotif] write FAILED: $e');
            rethrow;
          }
        } else {
          debugPrint('[CommentNotif] skipped (self-comment or missing '
              'postAuthorUid)');
        }
      }
    } catch (e) {
      // Notification is best-effort — comment was already saved.
      debugPrint('[CommentNotif] outer catch: $e');
    }
  }

  /// Updates the text of an existing comment / answer. Stamps an
  /// `editedAt` server timestamp so UI can render an "edited" hint if
  /// it wants to. Caller is responsible for authz (UI gates the edit
  /// button to the author).
  ///
  /// Re-runs the profanity filter on the new text and migrates the
  /// comment between the public `comments` path and the per-user
  /// `privateComments` path as needed so the visibility state matches
  /// the new content. A sender-only comment whose edit cleans up the
  /// word is promoted to public; a public comment that picks up a bad
  /// word is moved to sender-only.
  Future<void> editComment({
    required String postId,
    required String commentId,
    required String newText,
    bool senderOnly = false,
    String? currentUid,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final matches = await _profanityFilter.findMatches(trimmed);
    final flagged = matches.isNotEmpty;

    // Sender-only path → may need to PROMOTE to public if the new text
    // is clean. Either way the existing private doc needs touching.
    if (senderOnly) {
      if (currentUid == null || currentUid.isEmpty) {
        throw ArgumentError('currentUid is required for sender-only edits');
      }
      final privateRef =
          _privateComments(postId, currentUid).doc(commentId);
      if (flagged) {
        // Still bad — update in place, keep the flags.
        await privateRef.update({
          'text': trimmed,
          'editedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      // Cleaned up: copy the doc to the public collection, drop the
      // private copy, bump the post's public comment count.
      final snap = await privateRef.get();
      final old = snap.data() ?? {};
      final publicRef = _comments(postId).doc();
      final batch = _db.batch();
      batch.set(publicRef, {
        'authorUid': old['authorUid'],
        'authorUsername': old['authorUsername'],
        'authorAvatar': old['authorAvatar'],
        'text': trimmed,
        'createdAt': old['createdAt'] ?? FieldValue.serverTimestamp(),
        'editedAt': FieldValue.serverTimestamp(),
        'helpfulCount': old['helpfulCount'] ?? 0,
        'unhelpfulCount': old['unhelpfulCount'] ?? 0,
        if (old['parentCommentId'] != null)
          'parentCommentId': old['parentCommentId'],
        if (old['replyToUsername'] != null)
          'replyToUsername': old['replyToUsername'],
        // profanityFiltered + senderOnly intentionally omitted — the
        // new doc is public, no flags.
      });
      batch.delete(privateRef);
      batch.update(_postRef(postId),
          {'commentsCount': FieldValue.increment(1)});
      await batch.commit();
      return;
    }

    // Public path → only allow CLEAN edits. If the new text picks up a
    // bad word we reject the edit (keep the original visible to all
    // readers); the author already saw the warning that profanity is
    // blocked. This intentionally diverges from the addComment flow,
    // where a brand-new comment can land in the sender-only bucket —
    // editing a public comment into a flagged one would be a way to
    // sneak content past readers who already saw the clean version.
    final publicRef = _comments(postId).doc(commentId);
    if (!flagged) {
      await publicRef.update({
        'text': trimmed,
        'editedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    // Surface the rejection through an exception so the UI can show a
    // localized snackbar / toast. Callers should treat this as a
    // user-fixable error, not a service crash.
    throw const ProfanityEditRejected();
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
    bool senderOnly = false,
    String? currentUid,
  }) async {
    if (senderOnly) {
      if (currentUid == null || currentUid.isEmpty) {
        throw ArgumentError('currentUid is required for sender-only deletes');
      }
      await _privateComments(postId, currentUid).doc(commentId).delete();
      return;
    }

    final batch = _db.batch();
    batch.delete(_comments(postId).doc(commentId));
    batch.update(_postRef(postId), {
      'commentsCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  Future<void> toggleLikeComment({
    required String postId,
    required String commentId,
    required String uid,
  }) async {
    final likeRef = _likes(postId, commentId).doc(uid);
    bool wasLiked = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(likeRef);
      wasLiked = snap.exists;
      if (wasLiked) {
        tx.delete(likeRef);
      } else {
        tx.set(likeRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // Send / remove the notification outside the transaction (best-effort).
    try {
      final commentSnap = await _comments(postId).doc(commentId).get();
      final commentAuthorUid = commentSnap.data()?['authorUid'] as String?;
      if (commentAuthorUid != null && commentAuthorUid != uid) {
        final notifId = 'comment_like_${commentId}_$uid';
        if (wasLiked) {
          await _notifications.removeNotificationById(
              commentAuthorUid, notifId);
        } else {
          await _notifications.upsertNotification(
            targetUid: commentAuthorUid,
            docId: notifId,
            type: 'comment_like',
            actorUid: uid,
            targetId: postId,
            commentId: commentId,
          );
        }
      }
    } catch (_) {
      // Notification is best-effort — like was already toggled.
    }
  }

  Stream<bool> streamIsCommentLiked({
    required String postId,
    required String commentId,
    required String uid,
  }) {
    return _likes(postId, commentId)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Stream<int> streamCommentLikesCount({
    required String postId,
    required String commentId,
  }) {
    return _likes(postId, commentId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<String?> streamUserAnswerReaction({
    required String postId,
    required String commentId,
    required String uid,
  }) {
    return _reactions(postId, commentId)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.data()?['type'] as String?);
  }

  Future<void> setAnswerReaction({
    required String postId,
    required String commentId,
    required String uid,
    required String type,
  }) async {
    if (type != 'heart' && type != 'broken') {
      throw ArgumentError('type must be heart or broken');
    }

    final commentRef = _comments(postId).doc(commentId);
    final reactionRef = _reactions(postId, commentId).doc(uid);
    String? previousType;
    String? nextType;

    await _db.runTransaction((tx) async {
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists) return;

      final reactionSnap = await tx.get(reactionRef);
      previousType = reactionSnap.data()?['type'] as String?;
      nextType = previousType == type ? null : type;

      var helpful = (commentSnap.data()?['helpfulCount'] as num?)?.toInt() ?? 0;
      var unhelpful =
          (commentSnap.data()?['unhelpfulCount'] as num?)?.toInt() ?? 0;

      void dec(String t) {
        if (t == 'heart' && helpful > 0) helpful -= 1;
        if (t == 'broken' && unhelpful > 0) unhelpful -= 1;
      }

      void inc(String t) {
        if (t == 'heart') helpful += 1;
        if (t == 'broken') unhelpful += 1;
      }

      if (previousType == type) {
        dec(previousType!);
        tx.delete(reactionRef);
      } else {
        final prev = previousType;
        if (prev != null) dec(prev);
        inc(type);
        tx.set(reactionRef, {
          'type': type,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      tx.update(commentRef, {
        'helpfulCount': helpful,
        'unhelpfulCount': unhelpful,
      });
    });

    // Spark-safe fallback for answer reaction notifications in Q&A threads.
    try {
      final postSnap = await _postRef(postId).get();
      if ((postSnap.data()?['postType'] as String?) != 'qa') return;

      final commentSnap = await commentRef.get();
      final answerAuthorUid = commentSnap.data()?['authorUid'] as String?;
      if (answerAuthorUid == null || answerAuthorUid == uid) return;

      final likeNotifId = 'qa_answer_like_${postId}_${commentId}_$uid';
      final dislikeNotifId = 'qa_answer_dislike_${postId}_${commentId}_$uid';

      if (previousType == 'heart') {
        await _notifications.removeNotificationById(
            answerAuthorUid, likeNotifId);
      }
      if (previousType == 'broken') {
        await _notifications.removeNotificationById(
            answerAuthorUid, dislikeNotifId);
      }

      if (nextType == 'heart') {
        await _notifications.upsertNotification(
          targetUid: answerAuthorUid,
          docId: likeNotifId,
          type: 'qa_answer_like',
          actorUid: uid,
          targetId: postId,
          commentId: commentId,
        );
      }
      if (nextType == 'broken') {
        await _notifications.upsertNotification(
          targetUid: answerAuthorUid,
          docId: dislikeNotifId,
          type: 'qa_answer_dislike',
          actorUid: uid,
          targetId: postId,
          commentId: commentId,
        );
      }
    } catch (_) {
      // Notification is best-effort — reaction was already saved.
    }
  }
}
