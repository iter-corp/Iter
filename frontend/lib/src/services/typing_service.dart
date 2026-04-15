import 'package:firebase_database/firebase_database.dart';

// ─────────────────────────────────────────────
// Service  (Realtime Database path: typing/{chatId}/{uid})
// ─────────────────────────────────────────────

class TypingService {
  final DatabaseReference _root = FirebaseDatabase.instance.ref();

  /// Set or clear the typing flag for [uid] in [chatId].
  /// Also registers an onDisconnect remove so stale indicators are cleaned up.
  Future<void> setTyping(String chatId, String uid, bool isTyping) async {
    try {
      final ref = _root.child('typing/$chatId/$uid');
      if (isTyping) {
        await ref.set(true);
        await ref.onDisconnect().remove();
      } else {
        await ref.remove();
      }
    } catch (_) {
      // Fail silently if RTDB is not configured.
    }
  }

  /// Stream whether [otherUid] is currently typing in [chatId].
  Stream<bool> listenTyping(String chatId, String otherUid) {
    try {
      return _root
          .child('typing/$chatId/$otherUid')
          .onValue
          .map((event) => (event.snapshot.value as bool?) ?? false);
    } catch (_) {
      return Stream.value(false);
    }
  }
}
