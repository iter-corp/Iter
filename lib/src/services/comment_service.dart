import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/mention_utils.dart';
import 'notification_service.dart';
import 'profanity_filter_service.dart';
import 'user_service.dart';

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
  final int likesCount;
  final bool profanityFiltered;
  final bool senderOnly;

  /// Set by the question author to mark this answer as helpful. Helpful
  /// answers are sorted to the top and shown with a green check badge.
  final bool markedHelpful;

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
    this.likesCount = 0,
    this.profanityFiltered = false,
    this.senderOnly = false,
    this.markedHelpful = false,
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
      likesCount: (d['likesCount'] as num?)?.toInt() ?? 0,
      profanityFiltered: d['profanityFiltered'] == true,
      senderOnly: d['senderOnly'] == true,
      markedHelpful: d['markedHelpful'] == true,
    );
  }
}

class CommentService {
  final _db = FirebaseFirestore.instance;
  final NotificationService _notifications = NotificationService();
  final ProfanityFilterService _profanityFilter = ProfanityFilterService();
  final UserService _userService = UserService();

  Future<void> _processMentions(String text, String actorUid, String postId, String commentId) async {
    final usernames = MentionUtils.extractMentions(text);
    if (usernames.isEmpty) return;

    try {
      final uidMap = await _userService.getUidsByUsernames(usernames);
      final targetUids = uidMap.values.toList();
      await _notifications.sendMentionNotifications(
        targetUids: targetUids,
        actorUid: actorUid,
        targetId: postId,
        commentId: commentId,
      );
    } catch (e) {
      debugPrint('[CommentService] Error processing mentions: $e');
    }
  }

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

  Future<void> _backfillMissingLikesCount(
    String postId,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      if (doc.data().containsKey('likesCount')) continue;
      try {
        final likesSnap = await _likes(postId, doc.id).get();
        await doc.reference.set(
          {'likesCount': likesSnap.docs.length},
          SetOptions(merge: true),
        );
      } catch (_) {
        // Best-effort migration for older comments. A failed backfill should
        // not prevent the comment list from rendering.
      }
    }
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
    List<Comment> lastEmitted = const [];
    // Whether we've pushed at least one value. The de-dupe below would
    // otherwise swallow the very first emission for an empty thread (merged
    // == lastEmitted == []), leaving the StreamProvider stuck in `loading`
    // forever so the QA screen shows a spinner for questions with no answers.
    bool hasEmitted = false;

    void emitMerged() {
      final merged = [...publicComments, ...privateComments]..sort((a, b) {
          final aIsMine = a.authorUid == viewerUid;
          final bIsMine = b.authorUid == viewerUid;
          if (aIsMine != bIsMine) return aIsMine ? -1 : 1;

          final likesCompare = b.likesCount.compareTo(a.likesCount);
          if (likesCompare != 0) return likesCompare;

          final timeCompare = b.createdAt.compareTo(a.createdAt);
          if (timeCompare != 0) return timeCompare;

          return a.id.compareTo(b.id);
        });
      if (hasEmitted && _sameComments(lastEmitted, merged)) return;
      hasEmitted = true;
      lastEmitted = merged;
      if (!controller.isClosed) controller.add(merged);
    }

    controller.onListen = () {
      publicSub = _comments(postId)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) {
        debugPrint(
            '[CommentService] public comments snapshot: ${snap.docs.length} docs for post $postId');
        unawaited(_backfillMissingLikesCount(postId, snap.docs));
        publicComments = snap.docs.map(Comment.fromDoc).toList();
        emitMerged();
      }, onError: (Object e, StackTrace st) {
        debugPrint(
            '[CommentService] public comments error for post $postId: $e');
        if (!controller.isClosed) controller.addError(e, st);
      });

      privateSub = _privateComments(postId, viewerUid)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) {
        debugPrint(
            '[CommentService] private comments snapshot: ${snap.docs.length} docs for post $postId viewer $viewerUid');
        privateComments = snap.docs.map(Comment.fromDoc).toList();
        emitMerged();
      }, onError: (Object e, StackTrace st) {
        debugPrint(
            '[CommentService] private comments error for post $postId viewer $viewerUid: $e');
        if (!controller.isClosed) controller.addError(e, st);
      });
    };

    controller.onCancel = () async {
      await publicSub?.cancel();
      await privateSub?.cancel();
    };

    return controller.stream;
  }

  bool _sameComments(List<Comment> a, List<Comment> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.authorUid != right.authorUid ||
          left.authorUsername != right.authorUsername ||
          left.authorAvatar != right.authorAvatar ||
          left.text != right.text ||
          left.createdAt != right.createdAt ||
          left.parentCommentId != right.parentCommentId ||
          left.replyToUsername != right.replyToUsername ||
          left.helpfulCount != right.helpfulCount ||
          left.unhelpfulCount != right.unhelpfulCount ||
          left.likesCount != right.likesCount ||
          left.profanityFiltered != right.profanityFiltered ||
          left.senderOnly != right.senderOnly) {
        return false;
      }
    }
    return true;
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
      'likesCount': 0,
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

    await _processMentions(trimmed, authorUid, postId, commentRef.id);

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
          await _notifications.upsertNotification(
            targetUid: parentAuthorUid,
            docId: 'reply_${postId}_${commentRef.id}_$authorUid',
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
            await _notifications.upsertNotification(
              targetUid: postAuthorUid,
              docId: 'comment_${postId}_${commentRef.id}_$authorUid',
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
      final privateRef = _privateComments(postId, currentUid).doc(commentId);
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
      batch
          .update(_postRef(postId), {'commentsCount': FieldValue.increment(1)});
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
      final actorUid = currentUid ?? FirebaseAuth.instance.currentUser?.uid;
      if (actorUid != null) {
        await _processMentions(trimmed, actorUid, postId, commentId);
      }
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

    final commentRef = _comments(postId).doc(commentId);
    final commentSnap = await commentRef.get();
    final commentData = commentSnap.data();
    final commentAuthorUid = commentData?['authorUid'] as String?;
    final parentCommentId = commentData?['parentCommentId'] as String?;

    final batch = _db.batch();
    batch.delete(commentRef);
    batch.update(_postRef(postId), {
      'commentsCount': FieldValue.increment(-1),
    });
    await batch.commit();

    // Best-effort cleanup for the top-level "commented on your post"
    // notification, replies, and Q&A answer/reply notifications. The
    // deterministic IDs let the actor delete their own notification fan-out
    // without needing to query someone else's private notification list.
    try {
      final postSnap = await _postRef(postId).get();
      final postData = postSnap.data();
      final postAuthorUid = postData?['authorUid'] as String?;
      final isQa = (postData?['postType'] as String?) == 'qa';
      final isTopLevel = parentCommentId == null;

      if (commentAuthorUid == null) return;

      if (isTopLevel && postAuthorUid != null) {
        final notifId = isQa
            ? 'qa_answer_${postId}_${commentId}_$commentAuthorUid'
            : 'comment_${postId}_${commentId}_$commentAuthorUid';
        if (postAuthorUid != commentAuthorUid) {
          await _notifications.removeNotificationById(postAuthorUid, notifId);
        }
        return;
      }

      if (parentCommentId != null) {
        final parentSnap = await _comments(postId).doc(parentCommentId).get();
        final parentAuthorUid = parentSnap.data()?['authorUid'] as String?;
        if (parentAuthorUid == null || parentAuthorUid == commentAuthorUid) {
          return;
        }
        final notifId = isQa
            ? 'qa_reply_${postId}_${commentId}_$commentAuthorUid'
            : 'reply_${postId}_${commentId}_$commentAuthorUid';
        await _notifications.removeNotificationById(
          parentAuthorUid,
          notifId,
        );
      }
    } catch (_) {
      // Notification cleanup is best-effort; the comment is already deleted.
    }
  }

  Future<void> toggleLikeComment({
    required String postId,
    required String commentId,
    required String uid,
  }) async {
    final likeRef = _likes(postId, commentId).doc(uid);
    final commentRef = _comments(postId).doc(commentId);
    bool wasLiked = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(likeRef);
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists) return;

      wasLiked = snap.exists;
      if (wasLiked) {
        final currentCount =
            (commentSnap.data()?['likesCount'] as num?)?.toInt() ?? 1;
        tx.delete(likeRef);
        tx.update(commentRef, {
          'likesCount': currentCount > 0 ? currentCount - 1 : 0,
        });
      } else {
        tx.set(likeRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(commentRef, {'likesCount': FieldValue.increment(1)});
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

  /// Admin-side deletion of any comment/answer/reply. Mirrors
  /// [deleteComment] but doesn't gate on authorship (Firestore rules
  /// grant admins delete on all comment paths). Used when resolving a
  /// comment report by taking the comment down.
  Future<void> deleteCommentAsAdmin({
    required String postId,
    required String commentId,
  }) async {
    await _comments(postId).doc(commentId).delete();
  }

  /// Files a report against a comment, answer, or reply. Stored in the
  /// top-level `commentReports` collection so the admin "Comment reports"
  /// page can stream them alongside the other report types. [surface]
  /// records where it came from ('comment' | 'answer' | 'reply').
  Future<void> reportComment({
    required String postId,
    required Comment comment,
    required String reason,
    required String details,
    String surface = 'comment',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final reporter = await _db.collection('users').doc(uid).get();
    final reporterName = (reporter.data()?['username'] as String?) ?? 'user';
    await _db.collection('commentReports').add({
      'postId': postId,
      'commentId': comment.id,
      'commentText': comment.text,
      'commentAuthorUid': comment.authorUid,
      'commentAuthorUsername': comment.authorUsername,
      'commentAuthorAvatar': comment.authorAvatar,
      'surface': surface,
      'isReply': comment.isReply,
      'reporterUid': uid,
      'reporterUsername': reporterName,
      'reason': reason,
      'details': details,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// Toggles the "marked helpful" flag on an answer. Only the question's
  /// author should call this. [helpful] = true marks it; false unmarks it.
  Future<void> setAnswerHelpful({
    required String postId,
    required String commentId,
    required bool helpful,
  }) {
    return _comments(postId).doc(commentId).update({
      'markedHelpful': helpful,
    });
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
