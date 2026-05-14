import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminConfig {
  final bool storiesEnabled;
  final bool liveEnabled;
  final bool repostsEnabled;
  final bool translateEnabled;
  final String announcement;
  final bool maintenanceMode;
  final String minAppVersion;
  final String contactEmail;

  /// Public store links used by the in-app "Invite friends" share sheet.
  /// The app picks the right one for the running platform (iOS → App Store,
  /// Android → Google Play). Empty values fall back to the other store link
  /// or a generic message.
  final String iosAppStoreUrl;
  final String androidPlayStoreUrl;

  /// Event-type options admins choose from when creating an event and users
  /// filter notifications by. Editable from the admin dashboard; falls back to
  /// [kEventTypes] when unset/empty.
  final List<String> eventTypes;

  /// Country options admins tag events with and users filter notifications by.
  /// Editable from the admin dashboard; falls back to [kEventCountries] when
  /// unset/empty.
  final List<String> eventCountries;

  const AdminConfig({
    this.storiesEnabled = true,
    this.liveEnabled = true,
    this.repostsEnabled = true,
    this.translateEnabled = true,
    this.announcement = '',
    this.maintenanceMode = false,
    this.minAppVersion = '1.0.0',
    this.contactEmail = '',
    this.iosAppStoreUrl = '',
    this.androidPlayStoreUrl = '',
    this.eventTypes = kEventTypes,
    this.eventCountries = kEventCountries,
  });

  factory AdminConfig.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const {};
    List<String> cleanList(dynamic raw, List<String> fallback) {
      if (raw is! List) return fallback;
      final out = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return out.isEmpty ? fallback : out;
    }

    return AdminConfig(
      storiesEnabled: (m['storiesEnabled'] as bool?) ?? true,
      liveEnabled: (m['liveEnabled'] as bool?) ?? true,
      repostsEnabled: (m['repostsEnabled'] as bool?) ?? true,
      translateEnabled: (m['translateEnabled'] as bool?) ?? true,
      announcement: (m['announcement'] as String?) ?? '',
      maintenanceMode: (m['maintenanceMode'] as bool?) ?? false,
      minAppVersion: (m['minAppVersion'] as String?) ?? '1.0.0',
      contactEmail: (m['contactEmail'] as String?) ?? '',
      iosAppStoreUrl: (m['iosAppStoreUrl'] as String?) ?? '',
      androidPlayStoreUrl: (m['androidPlayStoreUrl'] as String?) ?? '',
      eventTypes: cleanList(m['eventTypes'], kEventTypes),
      eventCountries: cleanList(m['eventCountries'], kEventCountries),
    );
  }

  Map<String, dynamic> toMap() => {
        'storiesEnabled': storiesEnabled,
        'liveEnabled': liveEnabled,
        'repostsEnabled': repostsEnabled,
        'translateEnabled': translateEnabled,
        'announcement': announcement,
        'maintenanceMode': maintenanceMode,
        'minAppVersion': minAppVersion,
        'contactEmail': contactEmail,
        'iosAppStoreUrl': iosAppStoreUrl,
        'androidPlayStoreUrl': androidPlayStoreUrl,
        'eventTypes': eventTypes,
        'eventCountries': eventCountries,
      };

  AdminConfig copyWith({
    bool? storiesEnabled,
    bool? liveEnabled,
    bool? repostsEnabled,
    bool? translateEnabled,
    String? announcement,
    bool? maintenanceMode,
    String? minAppVersion,
    String? contactEmail,
    String? iosAppStoreUrl,
    String? androidPlayStoreUrl,
    List<String>? eventTypes,
    List<String>? eventCountries,
  }) {
    return AdminConfig(
      storiesEnabled: storiesEnabled ?? this.storiesEnabled,
      liveEnabled: liveEnabled ?? this.liveEnabled,
      repostsEnabled: repostsEnabled ?? this.repostsEnabled,
      translateEnabled: translateEnabled ?? this.translateEnabled,
      announcement: announcement ?? this.announcement,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      contactEmail: contactEmail ?? this.contactEmail,
      iosAppStoreUrl: iosAppStoreUrl ?? this.iosAppStoreUrl,
      androidPlayStoreUrl: androidPlayStoreUrl ?? this.androidPlayStoreUrl,
      eventTypes: eventTypes ?? this.eventTypes,
      eventCountries: eventCountries ?? this.eventCountries,
    );
  }
}

/// Canonical event-type options. Admins pick one when creating an event;
/// users can filter event notifications by these.
const List<String> kEventTypes = [
  'Scholarship',
  'Internship',
  'Research',
  'Conference',
  'Summer Program',
  'Competition',
  'Leadership',
  'Youth Summit',
  'other',
];

/// Canonical country options. Admins tag an event with the country it takes
/// place in; users filter event notifications by these. Keeping a curated
/// list (instead of free text) means the user's picks always match what the
/// admin chose. Stored lower-cased on the event doc as `locationCountry`.
const List<String> kEventCountries = [
  'Iraq',
  'Kurdistan Region',
  'Turkey',
  'Jordan',
  'Lebanon',
  'Egypt',
  'United Arab Emirates',
  'Saudi Arabia',
  'Qatar',
  'United Kingdom',
  'United States',
  'Germany',
  'France',
  'Italy',
  'Spain',
  'Netherlands',
  'Sweden',
  'Canada',
  'Australia',
  'Online',
];

class AdminEvent {
  final String id;
  final String title;
  final String subtitle;
  final String location;
  final String description;
  final String link;
  final String phone;
  final String email;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final DateTime? deadlineAt;

  /// One of [kEventTypes]; empty when the admin didn't set one (legacy events).
  final String eventType;

  /// One of [kEventCountries]; empty when the admin didn't set one (legacy
  /// events). Stored on the doc lower-cased as `locationCountry` for matching.
  final String country;

  /// Optional pin coordinates for the events map. Null when unknown.
  final double? lat;
  final double? lng;

  const AdminEvent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.description,
    required this.link,
    required this.phone,
    required this.email,
    required this.imageUrls,
    required this.createdAt,
    this.deadlineAt,
    this.eventType = '',
    this.country = '',
    this.lat,
    this.lng,
  });

  factory AdminEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final loc = d['geo'];
    final geoMap = loc is Map ? loc : null;
    return AdminEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      subtitle: (d['subtitle'] as String?) ?? '',
      location: (d['location'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      link: (d['link'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? const [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      deadlineAt: (d['deadline'] as Timestamp?)?.toDate(),
      eventType: (d['eventType'] as String?) ?? '',
      // `country` keeps the admin's original casing for display/editing;
      // `locationCountry` (lower-cased) is the matching key.
      country: ((d['country'] as String?)?.trim().isNotEmpty ?? false)
          ? (d['country'] as String).trim()
          : ((d['locationCountry'] as String?) ?? '').trim(),
      lat: (geoMap?['lat'] as num?)?.toDouble(),
      lng: (geoMap?['lng'] as num?)?.toDouble(),
    );
  }
}

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _configRef =>
      _db.collection('adminConfig').doc('app');

  Stream<AdminConfig> streamConfig() {
    return _configRef
        .snapshots()
        .map((snap) => AdminConfig.fromMap(snap.data()));
  }

  Future<void> saveConfig(AdminConfig cfg) {
    return _configRef.set(cfg.toMap(), SetOptions(merge: true));
  }

  // -------- Users --------
  Stream<List<Map<String, dynamic>>> streamUsers({String query = ''}) {
    return _db.collection('users').snapshots().map((snap) {
      final q = query.trim().toLowerCase();
      return snap.docs.map((d) => d.data()).where((u) {
        if (q.isEmpty) return true;
        final name = (u['username'] as String? ?? '').toLowerCase();
        final email = (u['email'] as String? ?? '').toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> suspendUser(String uid, bool suspended) =>
      _db.collection('users').doc(uid).update({'suspended': suspended});

  Future<void> setRole(String uid, String role) =>
      _db.collection('users').doc(uid).update({'role': role});

  /// Cascade-deletes ALL user data and adds their email to the blacklist.
  /// Runs client-side — relies on Firestore rules that grant admin delete
  /// permission on all traversed paths.
  Future<void> deleteUser(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final email = (userSnap.data()?['email'] as String?) ?? '';

    final posts =
        await _db.collection('posts').where('authorUid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await _deleteSubcollection(post.reference, 'likes');
      await _deleteSubcollection(post.reference, 'comments');
      await _deleteSubcollection(post.reference, 'reposts');
      await post.reference.delete();
    }

    final stories = await _db
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final story in stories.docs) {
      await _deleteSubcollection(story.reference, 'viewers');
      await story.reference.delete();
    }

    // Comments authored by the deleted user are intentionally kept on other
    // people's posts so the conversation history stays intact. The comment
    // tile renders "deleted user" when the author doc no longer exists.

    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final chat in chats.docs) {
      await _deleteSubcollection(chat.reference, 'messages');
      await chat.reference.delete();
    }

    final userRef = _db.collection('users').doc(uid);
    await _deleteSubcollection(userRef, 'followers');
    await _deleteSubcollection(userRef, 'following');
    await _deleteSubcollection(userRef, 'reposts');
    await _deleteSubcollection(userRef, 'saved');
    await _deleteSubcollection(userRef, 'savedTranslations');

    final followersOfOthers = await _db
        .collectionGroup('followers')
        .where('uid', isEqualTo: uid)
        .get();
    for (final doc in followersOfOthers.docs) {
      await doc.reference.delete();
    }
    final followingOfOthers = await _db
        .collectionGroup('following')
        .where('uid', isEqualTo: uid)
        .get();
    for (final doc in followingOfOthers.docs) {
      await doc.reference.delete();
    }

    await _deleteSubcollection(
        _db.collection('notifications').doc(uid), 'items');

    final regs = await _db
        .collection('eventRegistrations')
        .where('userUid', isEqualTo: uid)
        .get();
    for (final r in regs.docs) {
      await r.reference.delete();
    }

    await userRef.delete();

    if (email.isNotEmpty) {
      await _db.collection('blacklist').doc(email).set({
        'email': email,
        'uid': uid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Best-effort self-delete: the user removes their own data (what Firestore
  /// rules permit) and their Firebase Auth user. Leaves cross-user traces
  /// (followers on others, likes on others' posts) since collection-group
  /// writes aren't permitted for non-admin callers.
  Future<void> selfDeleteCurrentUser(String uid) async {
    // Capture the email FIRST so we can blacklist it even if some downstream
    // step fails. This is what stops the user from signing back in (via
    // Google, Apple, or a recreated email/password account).
    final userRef = _db.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final email = (userSnap.data()?['email'] as String?) ?? '';
    if (email.isNotEmpty) {
      try {
        await _db.collection('blacklist').doc(email).set({
          'email': email,
          'uid': uid,
          'deletedAt': FieldValue.serverTimestamp(),
          'selfDeleted': true,
        });
      } catch (_) {
        // Best-effort — if rules reject the write the auth-account delete
        // below is the only remaining gate.
      }
    }

    final posts =
        await _db.collection('posts').where('authorUid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await post.reference.delete();
    }

    final stories = await _db
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final story in stories.docs) {
      await story.reference.delete();
    }

    // Comments by this user are intentionally preserved; the comment tile
    // displays "deleted user" once the author doc is gone.

    await _deleteSubcollection(userRef, 'followers');
    await _deleteSubcollection(userRef, 'following');
    await _deleteSubcollection(userRef, 'reposts');
    await _deleteSubcollection(userRef, 'saved');
    await _deleteSubcollection(userRef, 'savedTranslations');

    await _deleteSubcollection(
        _db.collection('notifications').doc(uid), 'items');

    await userRef.delete();
  }

  Future<void> _deleteSubcollection(
      DocumentReference parent, String subcollection) async {
    final snap = await parent.collection(subcollection).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  // -------- Blacklist --------
  Stream<List<Map<String, dynamic>>> streamBlacklist() {
    return _db
        .collection('blacklist')
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Future<void> removeFromBlacklist(String email) =>
      _db.collection('blacklist').doc(email).delete();

  // -------- Posts --------
  Stream<List<Map<String, dynamic>>> streamAllPosts({int limit = 100}) {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  Future<void> deletePost(String postId) =>
      _db.collection('posts').doc(postId).delete();

  // -------- Events --------
  Stream<List<AdminEvent>> streamEvents() {
    return _db
        .collection('events')
        .snapshots()
        .map((s) => s.docs.map(AdminEvent.fromDoc).toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          }));
  }

  Future<String> createEvent({
    required String title,
    required String subtitle,
    required String location,
    required String description,
    required String link,
    required String phone,
    required String email,
    required List<String> imageUrls,
    DateTime? deadlineAt,
    String eventType = '',
    String country = '',
    double? lat,
    double? lng,
  }) async {
    final ref = await _db.collection('events').add({
      'title': title,
      'subtitle': subtitle,
      'location': location,
      'description': description,
      'link': link,
      'phone': phone,
      'email': email,
      'imageUrls': imageUrls,
      if (deadlineAt != null) 'deadline': Timestamp.fromDate(deadlineAt),
      'eventType': eventType,
      if (lat != null && lng != null) 'geo': {'lat': lat, 'lng': lng},
      // Lower-cased first segment of the location, kept for legacy callers.
      'locationCity': location.split(',').first.trim().toLowerCase(),
      // `country` is the admin's chosen label (original casing);
      // `locationCountry` is its lower-cased form, used by the event-notification
      // fan-out to match against users' selected countries.
      'country': country.trim(),
      'locationCountry': country.trim().toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Auto-create the matching event group chat so the admin sees it in
    // their inbox immediately, before any registrations are approved.
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (adminUid.isNotEmpty) {
      await _db.collection('eventChats').doc(ref.id).set({
        'eventId': ref.id,
        'eventTitle': title,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Spark-plan stand-in for the `onEventCreate` Cloud Function: fan the
    // `new_event` notification out to matching users right here, from the
    // admin's device. Best-effort — a failure here mustn't fail event
    // creation. (On Blaze, the Cloud Function would also do this; the
    // deterministic doc id `new_event_<eventId>` keeps it idempotent if both
    // ever ran.)
    try {
      await _fanOutNewEventNotifications(
        eventId: ref.id,
        title: title.trim(),
        subtitle: location.trim(),
        eventType: eventType.trim(),
        eventCountry: country.trim().toLowerCase(),
      );
    } catch (_) {
      // Swallow — the event still exists; notifications just didn't go out.
    }

    return ref.id;
  }

  /// Writes a `new_event` notification doc to every non-suspended user whose
  /// `eventNotifPrefs` matches the event. Mirrors `functions/src/events.ts`.
  Future<void> _fanOutNewEventNotifications({
    required String eventId,
    required String title,
    required String subtitle,
    required String eventType,
    required String eventCountry,
  }) async {
    final usersSnap = await _db.collection('users').get();

    bool wants(Map<String, dynamic> u) {
      if (u['suspended'] == true) return false;
      final prefs = (u['eventNotifPrefs'] as Map<String, dynamic>?) ?? const {};
      // Legacy 'cities' mode counts as on; its city list is no longer used.
      if ((prefs['mode'] as String?) == 'off') return false;

      // Policy: when the admin doesn't pick a type or country, the event is
      // treated as "general" and reaches every user whose notifications are
      // on, regardless of their type/country filters. The previous strict
      // matching silently filtered out everyone with a non-empty filter list
      // whenever an admin forgot to set a type, which made the whole
      // notification pipeline look broken from the user's side.
      final types = ((prefs['types'] as List?)?.map((e) => e.toString()) ??
              const <String>[])
          .toList();
      if (types.isNotEmpty && eventType.isNotEmpty) {
        if (!types.contains(eventType)) return false;
      }
      final countries = ((prefs['countries'] as List?)
                  ?.map((e) => e.toString().trim().toLowerCase()) ??
              const <String>[])
          .where((c) => c.isNotEmpty)
          .toList();
      if (countries.isNotEmpty && eventCountry.isNotEmpty) {
        if (!countries.contains(eventCountry)) return false;
      }
      return true;
    }

    var batch = _db.batch();
    var writes = 0;
    for (final doc in usersSnap.docs) {
      if (!wants(doc.data())) continue;
      final notifRef = _db
          .collection('notifications')
          .doc(doc.id)
          .collection('items')
          .doc('new_event_$eventId');
      batch.set(notifRef, {
        'type': 'new_event',
        'actorUid': '',
        'targetId': eventId,
        'title': title,
        'subtitle': subtitle,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      writes++;
      // Firestore batches cap at 500 writes.
      if (writes >= 450) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Keep the city search key in sync whenever the location changes.
    if (payload['location'] is String) {
      payload['locationCity'] =
          (payload['location'] as String).split(',').first.trim().toLowerCase();
    }
    // Keep the matching key in sync with the chosen country label.
    if (payload['country'] is String) {
      final c = (payload['country'] as String).trim();
      payload['country'] = c;
      payload['locationCountry'] = c.toLowerCase();
    }
    if (payload['deadline'] is DateTime) {
      payload['deadline'] = Timestamp.fromDate(payload['deadline'] as DateTime);
    }
    await _db.collection('events').doc(id).update(payload);
    // Keep the chat doc's title mirrored when the admin renames the event.
    if (payload.containsKey('title')) {
      await _db
          .collection('eventChats')
          .doc(id)
          .set({'eventTitle': payload['title']}, SetOptions(merge: true));
    }
  }

  /// Delete an event and, optionally, its linked group chat. The chat
  /// doc lives at `eventChats/{eventId}`; deleting it stops it from
  /// surfacing in members' inboxes. We delete the doc itself; pending
  /// messages cleanup is left to a backend trigger / TTL since
  /// recursive subcollection deletes aren't supported client-side.
  Future<void> deleteEvent(String id, {bool deleteChat = false}) async {
    final batch = _db.batch();
    batch.delete(_db.collection('events').doc(id));
    if (deleteChat) {
      batch.delete(_db.collection('eventChats').doc(id));
    }
    await batch.commit();
  }
}
