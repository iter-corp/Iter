import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'realtime_client.dart';

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
// Service  (WebSocket-backed realtime presence)
// ─────────────────────────────────────────────

class PresenceService {
  final Map<String, PresenceData> _cache = {};

  Future<void> setOnline(String uid) async {
    await RealtimeClient.instance.connect();
    _cache[uid] = PresenceData(online: true, lastSeen: DateTime.now());
  }

  Future<void> setOffline(String uid) async {
    _cache[uid] = PresenceData(online: false, lastSeen: DateTime.now());
  }

  /// Stream the presence state of any user via WebSocket events.
  Stream<PresenceData> listenPresence(String uid) {
    final initial = _cache[uid] ?? const PresenceData(online: false);

    return RealtimeClient.instance.presenceStream
        .where((event) => event['uid'] == uid)
        .map((event) {
          final online = event['online'] == true;
          final lastSeenMs = event['lastSeen'] as int?;
          final lastSeen = lastSeenMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
              : null;
          final data = PresenceData(online: online, lastSeen: lastSeen);
          _cache[uid] = data;
          return data;
        })
        .startWith(initial);
  }
}
