import 'package:firebase_database/firebase_database.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

class PresenceData {
  final bool online;
  final DateTime? lastSeen;

  const PresenceData({required this.online, this.lastSeen});

  String get statusText {
    if (online) return 'Online';
    if (lastSeen == null) return '';
    final d = DateTime.now().difference(lastSeen!);
    if (d.inSeconds < 60) return 'last seen just now';
    if (d.inMinutes < 60) return 'last seen ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'last seen ${d.inHours}h ago';
    return 'last seen ${d.inDays}d ago';
  }
}

// ─────────────────────────────────────────────
// Service  (Realtime Database path: presence/{uid})
// ─────────────────────────────────────────────

class PresenceService {
  final DatabaseReference _root = FirebaseDatabase.instance.ref();

  /// Mark the user as online and register an onDisconnect handler so Firebase
  /// automatically marks them offline if the connection drops.
  Future<void> setOnline(String uid) async {
    try {
      final ref = _root.child('presence/$uid');
      await ref.update({
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });
      await ref.onDisconnect().update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {
      // RTDB may not be configured yet — fail silently.
    }
  }

  /// Explicitly mark the user as offline (called on sign-out).
  Future<void> setOffline(String uid) async {
    try {
      await _root.child('presence/$uid').update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// Stream the presence state of any user.
  Stream<PresenceData> listenPresence(String uid) {
    try {
      return _root.child('presence/$uid').onValue.map((event) {
        final data = event.snapshot.value as Map?;
        if (data == null) return const PresenceData(online: false);
        final lastSeenMs = data['lastSeen'] as int?;
        return PresenceData(
          online: (data['online'] as bool?) ?? false,
          lastSeen: lastSeenMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
              : null,
        );
      });
    } catch (_) {
      return Stream.value(const PresenceData(online: false));
    }
  }
}
