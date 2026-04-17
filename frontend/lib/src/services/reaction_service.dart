import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Popular reaction emojis — same set used on event chats and 1:1 chats.
const List<String> kReactionEmojis = ['❤️', '👍', '😂', '😮', '😢', '🔥'];

/// Reactions live under a message at:
///   {parentPath}/{messageId}/reactions/{uid}
/// parentPath is e.g. "chats/{chatId}/messages" or
/// "eventChats/{eventId}/messages". This lets us reuse the logic on any
/// message type.
class ReactionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _reactionDoc(
    String parentPath,
    String messageId,
    String uid,
  ) =>
      _db.doc('$parentPath/$messageId/reactions/$uid');

  CollectionReference<Map<String, dynamic>> _reactionsCol(
    String parentPath,
    String messageId,
  ) =>
      _db.collection('$parentPath/$messageId/reactions');

  /// Toggle a reaction by the current user. If they already reacted with
  /// [emoji], the reaction is cleared; otherwise the emoji is set/replaced.
  Future<void> toggle({
    required String parentPath,
    required String messageId,
    required String emoji,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref = _reactionDoc(parentPath, messageId, user.uid);
    final existing = await ref.get();
    if (existing.exists && existing.data()?['emoji'] == emoji) {
      await ref.delete();
    } else {
      await ref.set({
        'emoji': emoji,
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Stream all reactions for a message as a map of emoji -> count.
  Stream<Map<String, int>> streamCounts({
    required String parentPath,
    required String messageId,
  }) {
    return _reactionsCol(parentPath, messageId).snapshots().map((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final emoji = doc.data()['emoji'] as String?;
        if (emoji == null) continue;
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Stream the current user's own reaction emoji (null = none).
  Stream<String?> streamMine({
    required String parentPath,
    required String messageId,
  }) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _reactionDoc(parentPath, messageId, uid)
        .snapshots()
        .map((s) => s.data()?['emoji'] as String?);
  }
}
