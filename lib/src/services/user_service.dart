import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

/// Maps a personalization goal (from `kProfileGoalOptions`, e.g. "Internships")
/// to the matching event-type tags (from `kEventTypes`, e.g. "Internship").
///
/// Used to keep a user's event-notification type filter in sync with the goals
/// they pick at onboarding / profile edit. Goals with no clear event-type
/// counterpart ("Networking", "Local events") map to nothing, so they simply
/// don't add a type filter.
const Map<String, List<String>> kGoalToEventTypes = {
  'Internships': ['Internship'],
  'Scholarships': ['Scholarship'],
  'Conferences': ['Conference'],
  'Research': ['Research'],
  'Networking': [],
  'Local events': [],
};

/// Translates a list of profile [goals] into the de-duplicated set of event
/// types they imply. Order follows `kEventTypes` so the result is stable.
List<String> eventTypesForGoals(List<String> goals) {
  final out = <String>{};
  for (final g in goals) {
    out.addAll(kGoalToEventTypes[g] ?? const []);
  }
  return out.toList();
}

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  Stream<EventNotifPrefs> streamEventNotifPrefs(String uid) =>
      _doc(uid).snapshots().map((s) => EventNotifPrefs.fromMap(
          s.data()?['eventNotifPrefs'] as Map<String, dynamic>?));

  Future<void> setEventNotifPrefs(String uid, EventNotifPrefs prefs) =>
      _doc(uid)
          .set({'eventNotifPrefs': prefs.toMap()}, SetOptions(merge: true));

  /// One-way sync: when the user changes their personalization [goals], fold
  /// the event types those goals imply into their event-notification type
  /// filter. This is intentionally additive and one-directional — changing
  /// goals updates notification prefs, but changing notification prefs never
  /// touches goals.
  ///
  /// Behaviour:
  /// * Goal-derived types are merged into any existing `types` (we never drop
  ///   a type the user added manually).
  /// * If notifications are off, we leave `mode` off — picking a goal should
  ///   not silently re-enable alerts the user turned off.
  /// * If the goals imply no event types ("Networking", "Local events" only),
  ///   nothing is written.
  Future<void> syncEventNotifTypesFromGoals(
    String uid,
    List<String> goals,
  ) async {
    final goalTypes = eventTypesForGoals(goals);
    if (goalTypes.isEmpty) return;

    final snap = await _doc(uid).get();
    final current = EventNotifPrefs.fromMap(
        snap.data()?['eventNotifPrefs'] as Map<String, dynamic>?);

    // Merge goal-derived types into the existing filter, preserving order
    // (existing types first, then any newly implied ones).
    final merged = <String>[
      ...current.types,
      ...goalTypes.where((t) => !current.types.contains(t)),
    ];
    if (merged.length == current.types.length) return; // nothing new

    await setEventNotifPrefs(uid, current.copyWith(types: merged));
  }

  Future<void> reportUserProfile({
    required String targetUid,
    required String targetUsername,
    String? targetAvatar,
    required String reason,
    String details = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    if (targetUid == user.uid) {
      throw Exception('You cannot report your own profile');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final reporterUsername = userDoc.data()?['username'] as String? ?? 'user';

    final reportId = '${targetUid}_${user.uid}';
    final reportRef = _db.collection('userReports').doc(reportId);
    final existing = await reportRef.get();
    if (existing.exists) {
      throw Exception('You already reported this profile');
    }

    final cleanedDetails = details.trim();
    await reportRef.set({
      'targetUid': targetUid,
      'targetUsername': targetUsername.trim(),
      'targetAvatar': targetAvatar,
      'reporterUid': user.uid,
      'reporterUsername': reporterUsername,
      'reason': reason.trim(),
      'details': cleanedDetails.isEmpty ? null : cleanedDetails,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
    });
  }

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

  /// Resolves a list of usernames to their corresponding UIDs.
  Future<Map<String, String>> getUidsByUsernames(List<String> usernames) async {
    final Map<String, String> result = {};
    if (usernames.isEmpty) return result;

    // Remove duplicates and normalize
    final uniqueUsernames =
        usernames.map(normalizeUsername).toSet().toList();

    // Firestore `in` queries are limited to 10 items per batch
    for (var i = 0; i < uniqueUsernames.length; i += 10) {
      final chunk = uniqueUsernames.sublist(
        i,
        i + 10 > uniqueUsernames.length ? uniqueUsernames.length : i + 10,
      );

      try {
        final snap = await _db
            .collection('users')
            .where('usernameLower', whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final docUsername =
              (doc.data()['username'] as String?)?.toLowerCase() ?? '';
          if (docUsername.isNotEmpty) {
            result[docUsername] = doc.id;
          }
        }
      } catch (e) {
        // Continue with the next chunk if one fails
      }
    }

    return result;
  }
}
