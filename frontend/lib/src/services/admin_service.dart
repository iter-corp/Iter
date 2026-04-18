import 'package:cloud_firestore/cloud_firestore.dart';

class AdminConfig {
  final bool storiesEnabled;
  final bool liveEnabled;
  final bool repostsEnabled;
  final bool translateEnabled;
  final String announcement;
  final bool maintenanceMode;
  final String minAppVersion;
  final String contactEmail;

  const AdminConfig({
    this.storiesEnabled = true,
    this.liveEnabled = true,
    this.repostsEnabled = true,
    this.translateEnabled = true,
    this.announcement = '',
    this.maintenanceMode = false,
    this.minAppVersion = '1.0.0',
    this.contactEmail = '',
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
      contactEmail: (m['contactEmail'] as String?) ?? '',
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
  Future<void> deleteUser(String uid) async {
    // 1. Get user email before deletion for blacklist.
    final userSnap = await _db.collection('users').doc(uid).get();
    final email = (userSnap.data()?['email'] as String?) ?? '';

    // 2. Delete user's posts and their subcollections (likes, comments, reposts).
    final posts = await _db
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final post in posts.docs) {
      await _deleteSubcollection(post.reference, 'likes');
      await _deleteSubcollection(post.reference, 'comments');
      await _deleteSubcollection(post.reference, 'reposts');
      await post.reference.delete();
    }

    // 3. Delete user's stories and their viewers.
    final stories = await _db
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final story in stories.docs) {
      await _deleteSubcollection(story.reference, 'viewers');
      await story.reference.delete();
    }

    // 4. Delete user's comments on other posts.
    final comments = await _db
        .collectionGroup('comments')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final c in comments.docs) {
      await c.reference.delete();
    }

    // 5. Delete chats where user is participant.
    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final chat in chats.docs) {
      await _deleteSubcollection(chat.reference, 'messages');
      await chat.reference.delete();
    }

    // 6. Delete followers/following subcollections.
    final userRef = _db.collection('users').doc(uid);
    await _deleteSubcollection(userRef, 'followers');
    await _deleteSubcollection(userRef, 'following');
    await _deleteSubcollection(userRef, 'reposts');
    await _deleteSubcollection(userRef, 'saved');

    // 7. Remove user from others' followers/following lists.
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

    // 8. Delete notifications.
    await _deleteSubcollection(
        _db.collection('notifications').doc(uid), 'items');

    // 9. Delete event registrations.
    final regs = await _db
        .collection('eventRegistrations')
        .where('uid', isEqualTo: uid)
        .get();
    for (final r in regs.docs) {
      await r.reference.delete();
    }

    // 10. Delete the user document itself.
    await userRef.delete();

    // 11. Add email to blacklist.
    if (email.isNotEmpty) {
      await _db.collection('blacklist').doc(email).set({
        'email': email,
        'uid': uid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Helper to delete all documents in a subcollection.
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
        .map((s) =>
            s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
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
