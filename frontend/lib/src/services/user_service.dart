import 'package:cloud_firestore/cloud_firestore.dart';

/// How a user wants to be notified about new events.
enum EventNotifMode {
  /// Every new event, anywhere.
  all,

  /// Only events whose city is in [EventNotifPrefs.cities].
  cities,

  /// No new-event notifications at all.
  off,
}

class EventNotifPrefs {
  final EventNotifMode mode;

  /// Lower-cased city names the user wants alerts for (only used when
  /// [mode] is [EventNotifMode.cities]).
  final List<String> cities;

  /// Event types (from `kEventTypes`) to limit alerts to. Empty = all types.
  final List<String> types;

  const EventNotifPrefs({
    this.mode = EventNotifMode.all,
    this.cities = const [],
    this.types = const [],
  });

  factory EventNotifPrefs.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const {};
    final modeStr = (m['mode'] as String?) ?? 'all';
    return EventNotifPrefs(
      mode: switch (modeStr) {
        'cities' => EventNotifMode.cities,
        'off' => EventNotifMode.off,
        _ => EventNotifMode.all,
      },
      cities: ((m['cities'] as List?)?.cast<String>() ?? const [])
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty)
          .toList(),
      types: (m['types'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': switch (mode) {
          EventNotifMode.cities => 'cities',
          EventNotifMode.off => 'off',
          EventNotifMode.all => 'all',
        },
        'cities': cities,
        'types': types,
      };

  EventNotifPrefs copyWith({
    EventNotifMode? mode,
    List<String>? cities,
    List<String>? types,
  }) =>
      EventNotifPrefs(
        mode: mode ?? this.mode,
        cities: cities ?? this.cities,
        types: types ?? this.types,
      );
}

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final snap = await _doc(uid).get();
    return snap.data();
  }

  Stream<Map<String, dynamic>?> streamUser(String uid) =>
      _doc(uid).snapshots().map((s) => s.data());

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      _doc(uid).set(data, SetOptions(merge: true));

  Stream<EventNotifPrefs> streamEventNotifPrefs(String uid) => _doc(uid)
      .snapshots()
      .map((s) => EventNotifPrefs.fromMap(
          s.data()?['eventNotifPrefs'] as Map<String, dynamic>?));

  Future<void> setEventNotifPrefs(String uid, EventNotifPrefs prefs) => _doc(uid)
      .set({'eventNotifPrefs': prefs.toMap()}, SetOptions(merge: true));

  String normalizeUsername(String username) => username.trim().toLowerCase();

  Future<bool> isUsernameTaken(
    String username, {
    String? excludeUid,
  }) async {
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return false;

    bool _containsOtherUid(QuerySnapshot<Map<String, dynamic>> snap) {
      return snap.docs.any((d) => excludeUid == null || d.id != excludeUid);
    }

    // Fast path for current schema.
    final byLower = await _db
        .collection('users')
        .where('usernameLower', isEqualTo: normalized)
        .limit(5)
        .get();
    if (_containsOtherUid(byLower)) return true;

    // Compatibility for docs that may only have lowercase username.
    final byExact = await _db
        .collection('users')
        .where('username', isEqualTo: normalized)
        .limit(5)
        .get();
    if (_containsOtherUid(byExact)) return true;

    // Legacy fallback: compare case-insensitively for older docs where
    // usernameLower may be missing and username had mixed casing.
    final allUsers = await _db.collection('users').get();
    for (final doc in allUsers.docs) {
      if (excludeUid != null && doc.id == excludeUid) continue;
      final existing = (doc.data()['username'] as String?) ?? '';
      if (normalizeUsername(existing) == normalized) return true;
    }
    return false;
  }
}
