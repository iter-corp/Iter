import 'dart:async';

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

  /// How often a foregrounded user re-stamps `lastSeen` while online, so a
  /// reader's staleness check never trips for someone who is actually
  /// active. Kept well under [_staleThreshold].
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  Timer? _heartbeatTimer;
  String? _heartbeatUid;

  /// Mark the user as online and register an onDisconnect handler so Firebase
  /// automatically marks them offline if the connection drops. Also starts a
  /// periodic heartbeat that refreshes `lastSeen` (and re-arms onDisconnect),
  /// so a stale write from a previous/zombie session can't leave the user
  /// looking offline to others while they're actually active.
  Future<void> setOnline(String uid) async {
    _startHeartbeat(uid);
    await _writeOnline(uid);
  }

  Future<void> _writeOnline(String uid) async {
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

  void _startHeartbeat(String uid) {
    // Restart cleanly if the active user changed (account switch).
    if (_heartbeatUid != uid) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
    _heartbeatUid = uid;
    _heartbeatTimer ??= Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_writeOnline(uid)),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatUid = null;
  }

  /// Explicitly mark the user as offline (called on sign-out / background).
  Future<void> setOffline(String uid) async {
    _stopHeartbeat();
    try {
      await _root.child('presence/$uid').update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// How long after the last heartbeat an `online: true` record is still
  /// trusted. If a session dies without its `onDisconnect` firing (force
  /// kill, lost socket, a zombie second device), the node can be left
  /// stuck at `online: true` forever. Past this window we treat it as
  /// offline so viewers don't see a permanently-"online" ghost — and,
  /// conversely, a user who really is active keeps heartbeating well
  /// within it. Must stay comfortably larger than [_heartbeatInterval].
  static const Duration _staleThreshold = Duration(seconds: 90);

  /// Stream the presence state of any user.
  Stream<PresenceData> listenPresence(String uid) {
    try {
      return _root.child('presence/$uid').onValue.map((event) {
        final data = event.snapshot.value as Map?;
        if (data == null) return const PresenceData(online: false);
        final lastSeenMs = data['lastSeen'] as int?;
        final lastSeen = lastSeenMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
            : null;
        var online = (data['online'] as bool?) ?? false;
        // Guard against stale `online: true` records left behind by a
        // session that never ran its onDisconnect handler. If the last
        // heartbeat is older than the threshold, the writer is gone.
        if (online && lastSeen != null) {
          if (DateTime.now().difference(lastSeen) > _staleThreshold) {
            online = false;
          }
        }
        return PresenceData(online: online, lastSeen: lastSeen);
      });
    } catch (_) {
      return Stream.value(const PresenceData(online: false));
    }
  }
}
