import 'package:cloud_firestore/cloud_firestore.dart';

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
enum ContactRequestStatus { open, answered, promoted }

ContactRequestStatus _statusFromRaw(Object? raw) {
  if (raw is String) {
    if (raw == 'answered') return ContactRequestStatus.answered;
    if (raw == 'promoted') return ContactRequestStatus.promoted;
  }
  return ContactRequestStatus.open;
}

String _statusToRaw(ContactRequestStatus s) {
  switch (s) {
    case ContactRequestStatus.answered:
      return 'answered';
    case ContactRequestStatus.promoted:
      return 'promoted';
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
    final now = FieldValue.serverTimestamp();
    final docRef = _col.doc();
    final subject = body.length > 60 ? '${body.substring(0, 59)}…' : body;
    await docRef.set({
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
    await docRef.collection('messages').add({
      'senderUid': userUid,
      'senderRole': 'user',
      'body': body,
      'createdAt': now,
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
      // First admin reply transitions the thread to answered. Don't
      // downgrade a promoted thread.
      update['status'] = _statusToRaw(ContactRequestStatus.answered);
    }
    await docRef.set(update, SetOptions(merge: true));
  }

  /// Stream of the signed-in user's own contact threads, newest first.
  Stream<List<ContactRequest>> streamMyRequests(String userUid) {
    return _col
        .where('userUid', isEqualTo: userUid)
        .snapshots()
        .map((s) {
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
  }
}
