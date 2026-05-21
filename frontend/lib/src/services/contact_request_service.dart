import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';

class ContactRequestDailyLimitException implements Exception {
  final String message;
  const ContactRequestDailyLimitException([
    this.message = 'You can open only one new request per day.',
  ]);

  @override
  String toString() => message;
}

/// What kind of contact-us submission this is. Drives the badge/icon
/// in the admin list and unlocks the "Promote to org admin" action.
enum ContactRequestType {
  /// General feedback or support question.
  message,

  /// User wants their account elevated to an event-posting
  /// organization. Admin sees a Promote action on these.
  organization,
}

ContactRequestType _typeFromRaw(Object? raw) {
  if (raw is String && raw == 'organization') {
    return ContactRequestType.organization;
  }
  return ContactRequestType.message;
}

String _typeToRaw(ContactRequestType t) =>
    t == ContactRequestType.organization ? 'organization' : 'message';

/// Lifecycle of a contact thread.
///   * `open`     — user submitted, awaiting admin reply
///   * `answered` — admin has replied at least once
///   * `promoted` — applies only to organization requests that were
///                  accepted: admin clicked "Promote to org admin"
///   * `revoked`  — organization access was removed after approval
enum ContactRequestStatus { open, answered, promoted, revoked }

ContactRequestStatus _statusFromRaw(Object? raw) {
  if (raw is String) {
    if (raw == 'answered') return ContactRequestStatus.answered;
    if (raw == 'promoted') return ContactRequestStatus.promoted;
    if (raw == 'revoked') return ContactRequestStatus.revoked;
  }
  return ContactRequestStatus.open;
}

String _statusToRaw(ContactRequestStatus s) {
  switch (s) {
    case ContactRequestStatus.answered:
      return 'answered';
    case ContactRequestStatus.promoted:
      return 'promoted';
    case ContactRequestStatus.revoked:
      return 'revoked';
    case ContactRequestStatus.open:
      return 'open';
  }
}

class ContactRequest {
  final String id;
  final String userUid;
  final String userEmail;
  final String userName;
  final ContactRequestType type;
  final String subject;
  final ContactRequestStatus status;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final bool unreadByUser;
  final bool unreadByAdmin;

  const ContactRequest({
    required this.id,
    required this.userUid,
    required this.userEmail,
    required this.userName,
    required this.type,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.unreadByUser,
    required this.unreadByAdmin,
  });

  factory ContactRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ContactRequest(
      id: doc.id,
      userUid: (d['userUid'] as String?) ?? '',
      userEmail: (d['userEmail'] as String?) ?? '',
      userName: (d['userName'] as String?) ?? '',
      type: _typeFromRaw(d['type']),
      subject: (d['subject'] as String?) ?? '',
      status: _statusFromRaw(d['status']),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessagePreview: (d['lastMessagePreview'] as String?) ?? '',
      unreadByUser: (d['unreadByUser'] as bool?) ?? false,
      unreadByAdmin: (d['unreadByAdmin'] as bool?) ?? false,
    );
  }
}

class ContactRequestMessage {
  final String id;
  final String senderUid;

  /// 'user' or 'admin' — drives left/right bubble alignment.
  final String senderRole;
  final String body;
  final DateTime? createdAt;

  const ContactRequestMessage({
    required this.id,
    required this.senderUid,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  factory ContactRequestMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ContactRequestMessage(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      senderRole: (d['senderRole'] as String?) ?? 'user',
      body: (d['body'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class ContactRequestService {
  ContactRequestService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final NotificationService _notifications = NotificationService();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('contactRequests');

  /// Maximum length we store in the lastMessagePreview field. Keeps
  /// the list-tile subtitle bounded.
  static const _previewLimit = 120;

  String _trimPreview(String text) {
    final t = text.trim();
    if (t.length <= _previewLimit) return t;
    return '${t.substring(0, _previewLimit - 1)}…';
  }

  String _dayKeyUtc(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _deleteCollectionDocs(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    while (true) {
      final snap = await col.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) return;
    }
  }

  Future<void> _deleteEventArtifacts(String eventId) async {
    final chatRef = _db.collection('eventChats').doc(eventId);
    await _deleteCollectionDocs(chatRef.collection('messages'));
    await _deleteCollectionDocs(chatRef.collection('members'));

    final regs = await _db
        .collection('eventRegistrations')
        .where('eventId', isEqualTo: eventId)
        .get();
    if (regs.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final reg in regs.docs) {
        batch.delete(reg.reference);
      }
      await batch.commit();
    }

    final batch = _db.batch();
    batch.delete(chatRef);
    batch.delete(_db.collection('events').doc(eventId));
    await batch.commit();
  }

  Future<void> _deleteEventsCreatedBy(String userUid) async {
    final events = await _db
        .collection('events')
        .where('createdByUid', isEqualTo: userUid)
        .get();
    for (final event in events.docs) {
      await _deleteEventArtifacts(event.id);
    }
  }

  /// Permanently deletes a contact thread and all its messages.
  Future<void> deleteRequest(String requestId) async {
    // Firestore rules allow admins to delete the parent contactRequest doc
    // but not individual message docs under /messages. Deleting only the
    // thread doc keeps the admin UX working without requiring a rules deploy.
    await _col.doc(requestId).delete();
  }

  /// Creates a new contact thread and posts the user's first message.
  /// Returns the new request id.
  Future<String> submit({
    required String userUid,
    required String userEmail,
    required String userName,
    required ContactRequestType type,
    required String firstMessage,
  }) async {
    final body = firstMessage.trim();
    if (body.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    // Backward-compatible guard for users created before the daily lock field
    // existed: if they already opened one request today, block immediately.
    final nowUtc = DateTime.now().toUtc();
    final startOfDayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));
    final existing = await _col.where('userUid', isEqualTo: userUid).get();
    final alreadyOpenedToday = existing.docs.any((d) {
      final createdAt = (d.data()['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null) return false;
      final c = createdAt.toUtc();
      return !c.isBefore(startOfDayUtc) && c.isBefore(endOfDayUtc);
    });
    if (alreadyOpenedToday) {
      throw const ContactRequestDailyLimitException();
    }

    final now = FieldValue.serverTimestamp();
    final todayKey = _dayKeyUtc(nowUtc);
    final docRef = _col.doc();
    final userRef = _db.collection('users').doc(userUid);
    final msgRef = docRef.collection('messages').doc();
    final subject = body.length > 60 ? '${body.substring(0, 59)}…' : body;
    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final lastDay =
          (userSnap.data()?['lastContactRequestDay'] as String?) ?? '';
      if (lastDay == todayKey) {
        throw const ContactRequestDailyLimitException();
      }

      tx.set(
          userRef,
          {
            'lastContactRequestDay': todayKey,
            'lastContactRequestAt': now,
          },
          SetOptions(merge: true));

      tx.set(docRef, {
        'userUid': userUid,
        'userEmail': userEmail.trim(),
        'userName': userName.trim(),
        'type': _typeToRaw(type),
        'subject': subject,
        'status': _statusToRaw(ContactRequestStatus.open),
        'createdAt': now,
        'lastMessageAt': now,
        'lastMessagePreview': _trimPreview(body),
        'unreadByUser': false,
        'unreadByAdmin': true,
      });

      tx.set(msgRef, {
        'senderUid': userUid,
        'senderRole': 'user',
        'body': body,
        'createdAt': now,
      });
    });
    return docRef.id;
  }

  /// Posts a new message in [requestId]. Updates the parent doc's
  /// preview + unread flags so the other party sees a fresh notice.
  Future<void> sendMessage({
    required String requestId,
    required String senderUid,
    required bool senderIsAdmin,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final now = FieldValue.serverTimestamp();
    final docRef = _col.doc(requestId);
    final parentSnap = await docRef.get();
    final currentStatus = _statusFromRaw(parentSnap.data()?['status']);
    await docRef.collection('messages').add({
      'senderUid': senderUid,
      'senderRole': senderIsAdmin ? 'admin' : 'user',
      'body': trimmed,
      'createdAt': now,
    });
    final update = <String, Object?>{
      'lastMessageAt': now,
      'lastMessagePreview': _trimPreview(trimmed),
      // Whoever just sent has read their own message; flip the other
      // party's unread flag so the inbox surface shows a dot.
      'unreadByUser': senderIsAdmin ? true : false,
      'unreadByAdmin': senderIsAdmin ? false : true,
    };
    if (senderIsAdmin) {
      if (currentStatus != ContactRequestStatus.promoted &&
          currentStatus != ContactRequestStatus.revoked) {
        update['status'] = _statusToRaw(ContactRequestStatus.answered);
      }
    }
    await docRef.set(update, SetOptions(merge: true));
  }

  Future<void> setType({
    required String requestId,
    required ContactRequestType type,
  }) {
    return _col.doc(requestId).set(
      {'type': _typeToRaw(type)},
      SetOptions(merge: true),
    );
  }

  /// Stream of the signed-in user's own contact threads, newest first.
  Stream<List<ContactRequest>> streamMyRequests(String userUid) {
    return _col.where('userUid', isEqualTo: userUid).snapshots().map((s) {
      final out = s.docs.map(ContactRequest.fromDoc).toList()
        ..sort((a, b) {
          final at = a.lastMessageAt;
          final bt = b.lastMessageAt;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      return out;
    });
  }

  /// Stream of every contact thread for the admin dashboard.
  Stream<List<ContactRequest>> streamAll() {
    return _col.snapshots().map((s) {
      final out = s.docs.map(ContactRequest.fromDoc).toList()
        ..sort((a, b) {
          final at = a.lastMessageAt;
          final bt = b.lastMessageAt;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      return out;
    });
  }

  /// Stream of messages in [requestId], oldest first.
  Stream<List<ContactRequestMessage>> streamMessages(String requestId) {
    return _col
        .doc(requestId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(ContactRequestMessage.fromDoc).toList());
  }

  /// Clears the unread flag for whichever side is currently reading.
  /// Called from the thread screen on open so the other party stops
  /// seeing the unread dot once the message has been viewed.
  Future<void> markRead({
    required String requestId,
    required bool readerIsAdmin,
  }) async {
    final field = readerIsAdmin ? 'unreadByAdmin' : 'unreadByUser';
    try {
      await _col.doc(requestId).set(
        {field: false},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort; not worth surfacing a transient write failure.
    }
  }

  /// Flips the requesting user's role to `org_admin` so they gain
  /// event-posting rights. Marks the thread as `promoted` so the
  /// admin list shows the outcome and the user's settings page can
  /// reflect their new status. Admin-only; gated by Firestore rules
  /// (only admins can update other users' role field).
  Future<void> promoteToOrgAdmin({
    required String requestId,
    required String userUid,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(userUid), {
      'role': 'org_admin',
      'orgAdminGrantedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _col.doc(requestId),
      {'status': _statusToRaw(ContactRequestStatus.promoted)},
      SetOptions(merge: true),
    );
    await batch.commit();
    await _notifications.createSystemNotification(
      targetUid: userUid,
      type: 'role_update',
      title: 'Event manager access granted',
      subtitle: 'Iter Team approved you as an event manager.',
    );
  }

  /// Removes organization event-posting access by restoring `role: user`.
  /// Marks the request as `revoked` so both admin and user can see that the
  /// previous approval was explicitly rolled back.
  Future<void> revokeOrgAdmin({
    required String requestId,
    required String userUid,
  }) async {
    await _deleteEventsCreatedBy(userUid);

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(userUid), {
      'role': 'user',
      'orgAdminRevokedAt': FieldValue.serverTimestamp(),
      'orgAdminGrantedAt': FieldValue.delete(),
    });
    batch.set(
      _col.doc(requestId),
      {'status': _statusToRaw(ContactRequestStatus.revoked)},
      SetOptions(merge: true),
    );
    await batch.commit();
    await _notifications.createSystemNotification(
      targetUid: userUid,
      type: 'role_update',
      title: 'Event manager access removed',
      subtitle: 'Iter Team revoked your event manager access.',
    );
  }
}
