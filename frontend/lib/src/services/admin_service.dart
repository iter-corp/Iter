import 'package:cloud_firestore/cloud_firestore.dart';

class AdminConfig {
  final bool storiesEnabled;
  final bool liveEnabled;
  final bool repostsEnabled;
  final bool translateEnabled;
  final String announcement;
  final bool maintenanceMode;
  final String minAppVersion;

  const AdminConfig({
    this.storiesEnabled = true,
    this.liveEnabled = true,
    this.repostsEnabled = true,
    this.translateEnabled = true,
    this.announcement = '',
    this.maintenanceMode = false,
    this.minAppVersion = '1.0.0',
  });

  factory AdminConfig.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const {};
    return AdminConfig(
      storiesEnabled: (m['storiesEnabled'] as bool?) ?? true,
      liveEnabled: (m['liveEnabled'] as bool?) ?? true,
      repostsEnabled: (m['repostsEnabled'] as bool?) ?? true,
      translateEnabled: (m['translateEnabled'] as bool?) ?? true,
      announcement: (m['announcement'] as String?) ?? '',
      maintenanceMode: (m['maintenanceMode'] as bool?) ?? false,
      minAppVersion: (m['minAppVersion'] as String?) ?? '1.0.0',
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
      };

  AdminConfig copyWith({
    bool? storiesEnabled,
    bool? liveEnabled,
    bool? repostsEnabled,
    bool? translateEnabled,
    String? announcement,
    bool? maintenanceMode,
    String? minAppVersion,
  }) {
    return AdminConfig(
      storiesEnabled: storiesEnabled ?? this.storiesEnabled,
      liveEnabled: liveEnabled ?? this.liveEnabled,
      repostsEnabled: repostsEnabled ?? this.repostsEnabled,
      translateEnabled: translateEnabled ?? this.translateEnabled,
      announcement: announcement ?? this.announcement,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      minAppVersion: minAppVersion ?? this.minAppVersion,
    );
  }
}

class AdminEvent {
  final String id;
  final String title;
  final String subtitle;
  final String location;
  final String description;
  final String phone;
  final String email;
  final List<String> imageUrls;
  final DateTime? createdAt;

  const AdminEvent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.description,
    required this.phone,
    required this.email,
    required this.imageUrls,
    required this.createdAt,
  });

  factory AdminEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AdminEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      subtitle: (d['subtitle'] as String?) ?? '',
      location: (d['location'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? const [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int _batchWriteLimit = 450;

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

  Future<void> suspendUser(String uid, bool suspended) => _db
      .collection('users')
      .doc(uid)
      .set({'suspended': suspended}, SetOptions(merge: true));

  Future<void> setRole(String uid, String role) =>
      _db.collection('users').doc(uid).update({'role': role});

  Future<void> deleteUser(String uid) async {
    await _deletePostsByAuthor(uid);
    await _deleteCommentsByAuthor(uid);
    await _deleteDocsByField('stories', 'authorUid', uid);
    await _deleteDocsByField('liveStreams', 'hostUid', uid);

    await _deleteUserSubcollection(uid, 'followers');
    await _deleteUserSubcollection(uid, 'following');
    await _deleteUserSubcollection(uid, 'reposts');
    await _deleteUserSubcollection(uid, 'saved');
    await _deleteUserSubcollection(uid, 'savedTranslations');

    await _deleteNotificationItems(uid);
    await _deleteFeedTimeline(uid);

    // Spark plan cannot delete Firebase Auth users server-side.
    // Keep a tombstone so the account is blocked in app login/route guards.
    await _db.collection('users').doc(uid).set(
      {
        'uid': uid,
        'deleted': true,
        'suspended': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'role': 'user',
        'username': '[deleted]',
        'handle': null,
        'bio': '',
        'avatarUrl': null,
        'coverUrl': null,
        'fcmTokens': <String>[],
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _deletePostsByAuthor(String authorUid) async {
    while (true) {
      final snap = await _db
          .collection('posts')
          .where('authorUid', isEqualTo: authorUid)
          .limit(50)
          .get();
      if (snap.docs.isEmpty) return;

      for (final postDoc in snap.docs) {
        await _deletePostWithSubcollections(postDoc.reference);
      }
    }
  }

  Future<void> _deletePostWithSubcollections(
    DocumentReference<Map<String, dynamic>> postRef,
  ) async {
    await _deleteCollection(postRef.collection('likes'));
    await _deleteCollection(postRef.collection('comments'));
    await _deleteCollection(postRef.collection('reposts'));
    await postRef.delete();
  }

  Future<void> _deleteCommentsByAuthor(String authorUid) async {
    while (true) {
      final snap = await _db
          .collectionGroup('comments')
          .where('authorUid', isEqualTo: authorUid)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;

      final decrements = <String, int>{};
      var batch = _db.batch();
      var writes = 0;

      for (final commentDoc in snap.docs) {
        final postRef = commentDoc.reference.parent.parent;
        if (postRef != null) {
          decrements[postRef.id] = (decrements[postRef.id] ?? 0) + 1;
        }

        batch.delete(commentDoc.reference);
        writes++;

        if (writes >= _batchWriteLimit) {
          await batch.commit();
          batch = _db.batch();
          writes = 0;
        }
      }

      for (final entry in decrements.entries) {
        batch.set(
          _db.collection('posts').doc(entry.key),
          {'commentsCount': FieldValue.increment(-entry.value)},
          SetOptions(merge: true),
        );
        writes++;

        if (writes >= _batchWriteLimit) {
          await batch.commit();
          batch = _db.batch();
          writes = 0;
        }
      }

      if (writes > 0) {
        await batch.commit();
      }
    }
  }

  Future<void> _deleteDocsByField(
    String collection,
    String field,
    String value,
  ) async {
    while (true) {
      final snap = await _db
          .collection(collection)
          .where(field, isEqualTo: value)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;

      var batch = _db.batch();
      var writes = 0;
      for (final d in snap.docs) {
        batch.delete(d.reference);
        writes++;

        if (writes >= _batchWriteLimit) {
          await batch.commit();
          batch = _db.batch();
          writes = 0;
        }
      }
      if (writes > 0) {
        await batch.commit();
      }
    }
  }

  Future<void> _deleteUserSubcollection(
      String uid, String subcollection) async {
    final col = _db.collection('users').doc(uid).collection(subcollection);
    await _deleteCollection(col);
  }

  Future<void> _deleteNotificationItems(String uid) async {
    final col = _db.collection('notifications').doc(uid).collection('items');
    await _deleteCollection(col);
  }

  Future<void> _deleteFeedTimeline(String uid) async {
    final col = _db.collection('feeds').doc(uid).collection('timeline');
    await _deleteCollection(col);
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snap = await collection.limit(200).get();
      if (snap.docs.isEmpty) return;

      var batch = _db.batch();
      var writes = 0;
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        writes++;
        if (writes >= _batchWriteLimit) {
          await batch.commit();
          batch = _db.batch();
          writes = 0;
        }
      }

      if (writes > 0) {
        await batch.commit();
      }
    }
  }

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
    required String phone,
    required String email,
    required List<String> imageUrls,
  }) async {
    final ref = await _db.collection('events').add({
      'title': title,
      'subtitle': subtitle,
      'location': location,
      'description': description,
      'phone': phone,
      'email': email,
      'imageUrls': imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) =>
      _db.collection('events').doc(id).update(data);

  Future<void> deleteEvent(String id) =>
      _db.collection('events').doc(id).delete();
}
