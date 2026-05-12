import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a user wants new-event notifications at all. The fine-grained
/// filtering (which types / which countries) lives in [EventNotifPrefs].
enum EventNotifMode {
  /// Receive new-event notifications (subject to the type/country filters).
  all,

  /// No new-event notifications at all.
  off,
}

class EventNotifPrefs {
  final EventNotifMode mode;

  /// Event types (from `kEventTypes`) to limit alerts to. Empty = all types
  /// ("All" is selected in the UI).
  final List<String> types;

  /// Lower-cased country names (from `kEventCountries`) to limit alerts to.
  /// Empty = all countries ("All" is selected in the UI).
  final List<String> countries;

  const EventNotifPrefs({
    this.mode = EventNotifMode.all,
    this.types = const [],
    this.countries = const [],
  });

  factory EventNotifPrefs.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const {};
    final modeStr = (m['mode'] as String?) ?? 'all';
    return EventNotifPrefs(
      // Legacy 'cities' mode is treated as on; its city list is discarded
      // since the model now filters by country.
      mode: modeStr == 'off' ? EventNotifMode.off : EventNotifMode.all,
      types: (m['types'] as List?)?.cast<String>() ?? const [],
      countries: ((m['countries'] as List?)?.cast<String>() ?? const [])
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': switch (mode) {
          EventNotifMode.off => 'off',
          EventNotifMode.all => 'all',
        },
        'types': types,
        'countries': countries,
      };

  EventNotifPrefs copyWith({
    EventNotifMode? mode,
    List<String>? types,
    List<String>? countries,
  }) =>
      EventNotifPrefs(
        mode: mode ?? this.mode,
        types: types ?? this.types,
        countries: countries ?? this.countries,
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
