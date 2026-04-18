import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const List<String> kReactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👍'];

class ReactionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Toggles a reaction on a message. If the user already reacted with the
  /// same emoji, the reaction is removed. If a different emoji, it's replaced.
  Future<void> toggle({
    required String parentPath,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final reactionsCol =
        _db.collection('$parentPath/$messageId/reactions');
    final docRef = reactionsCol.doc(uid);
    final snap = await docRef.get();

    if (snap.exists && snap.data()?['emoji'] == emoji) {
      await docRef.delete();
    } else {
      await docRef.set({
        'emoji': emoji,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Streams the current user's reaction emoji for a message, or null.
  Stream<String?> streamMyReaction({
    required String parentPath,
    required String messageId,
  }) {
    final uid = _uid;
    if (uid == null) return Stream.value(null);

    return _db
        .collection('$parentPath/$messageId/reactions')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.data()?['emoji'] as String?);
  }

  /// Streams aggregated emoji counts for a message.
  Stream<Map<String, int>> streamReactionCounts({
    required String parentPath,
    required String messageId,
  }) {
    return _db
        .collection('$parentPath/$messageId/reactions')
        .snapshots()
        .map((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final emoji = doc.data()['emoji'] as String?;
        if (emoji != null) {
          counts[emoji] = (counts[emoji] ?? 0) + 1;
        }
      }
      return counts;
    });
  }
}
