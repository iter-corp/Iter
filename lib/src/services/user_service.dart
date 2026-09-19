import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

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

const Map<String, List<String>> kGoalToEventTypes = {
  'Internships': ['Internship'],
  'Scholarships': ['Scholarship'],
  'Conferences': ['Conference'],
  'Research': ['Research'],
  'Networking': [],
  'Local events': [],
};

List<String> eventTypesForGoals(List<String> goals) {
  final out = <String>{};
  for (final g in goals) {
    out.addAll(kGoalToEventTypes[g] ?? const []);
  }
  return out.toList();
}

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Map<String, StreamController<Map<String, dynamic>?>> _userStreams = {};
  final Map<String, Map<String, dynamic>> _userCache = {};

  Future<Map<String, dynamic>?> getUser(String uid) async {
    try {
      final res = await ApiClient.instance.get('/users/$uid');
      if (res is Map<String, dynamic>) {
        _userCache[uid] = res;
        _userStreams[uid]?.add(res);
        return res;
      }
      return null;
    } catch (e) {
      debugPrint('[UserService] getUser error for $uid: $e');
      return _userCache[uid];
    }
  }

  void cacheUser(String uid, Map<String, dynamic> data) {
    _userCache[uid] = data;
    if (!(_userStreams[uid]?.isClosed ?? true)) {
      _userStreams[uid]?.add(data);
    }
  }

  Stream<Map<String, dynamic>?> streamUser(String uid) {
    if (!_userStreams.containsKey(uid) || _userStreams[uid]!.isClosed) {
      _userStreams[uid] = StreamController<Map<String, dynamic>?>.broadcast();
    }

    if (_userCache.containsKey(uid)) {
      Timer.run(() {
        if (!(_userStreams[uid]?.isClosed ?? true)) {
          _userStreams[uid]!.add(_userCache[uid]);
        }
      });
    }

    getUser(uid);
    return _userStreams[uid]!.stream;
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      final res = await ApiClient.instance.patch('/users/me', body: data);
      if (res is Map<String, dynamic>) {
        _userCache[uid] = res;
        _userStreams[uid]?.add(res);
      }
    } catch (e) {
      debugPrint('[UserService] updateUser error: $e');
      rethrow;
    }
  }

  Stream<EventNotifPrefs> streamEventNotifPrefs(String uid) =>
      streamUser(uid).map((d) => EventNotifPrefs.fromMap(
          d?['eventNotifPrefs'] as Map<String, dynamic>?));

  Future<void> setEventNotifPrefs(String uid, EventNotifPrefs prefs) =>
      updateUser(uid, {'eventNotifPrefs': prefs.toMap()});

  Future<void> syncEventNotifTypesFromGoals(
    String uid,
    List<String> goals,
  ) async {
    final goalTypes = eventTypesForGoals(goals);
    if (goalTypes.isEmpty) return;

    final user = await getUser(uid);
    final current = EventNotifPrefs.fromMap(
        user?['eventNotifPrefs'] as Map<String, dynamic>?);

    final merged = <String>[
      ...current.types,
      ...goalTypes.where((t) => !current.types.contains(t)),
    ];
    if (merged.length == current.types.length) return;

    await setEventNotifPrefs(uid, current.copyWith(types: merged));
  }

  Future<void> reportUserProfile({
    required String targetUid,
    required String targetUsername,
    String? targetAvatar,
    required String reason,
    String details = '',
  }) async {
    await ApiClient.instance.post('/users/$targetUid/report', body: {
      'reason': reason,
      'details': details,
    });
  }

  String normalizeUsername(String username) => username.trim().toLowerCase();

  Future<bool> isUsernameTaken(
    String username, {
    String? excludeUid,
  }) async {
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return false;

    try {
      final res = await ApiClient.instance.get(
        '/users/check-username',
        queryParams: {'username': normalized},
      );
      if (res is Map<String, dynamic>) {
        return res['available'] == false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> getUidsByUsernames(List<String> usernames) async {
    final Map<String, String> result = {};
    if (usernames.isEmpty) return result;

    for (final name in usernames) {
      try {
        final res = await ApiClient.instance.get(
          '/users/search',
          queryParams: {'q': name},
        );
        if (res is List) {
          for (final item in res) {
            if (item is Map<String, dynamic> &&
                (item['username'] as String?)?.toLowerCase() == name.toLowerCase()) {
              result[name.toLowerCase()] = item['id'] as String;
            }
          }
        }
      } catch (_) {}
    }

    return result;
  }
}
