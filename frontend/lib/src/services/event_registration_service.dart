import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';

enum RegistrationStatus { pending, approved, rejected }

RegistrationStatus _statusFrom(String? s) {
  switch (s) {
    case 'approved':
      return RegistrationStatus.approved;
    case 'rejected':
      return RegistrationStatus.rejected;
    default:
      return RegistrationStatus.pending;
  }
}

class EventRegistration {
  final String id;
  final String eventId;
  final String eventTitle;
  final String userUid;
  final String name;
  final String email;
  final String phone;
  final String countryCode;
  final RegistrationStatus status;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  const EventRegistration({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.userUid,
    required this.name,
    required this.email,
    required this.phone,
    required this.countryCode,
    required this.status,
    this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory EventRegistration.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return EventRegistration(
      id: doc.id,
      eventId: (d['eventId'] as String?) ?? '',
      eventTitle: (d['eventTitle'] as String?) ?? '',
      userUid: (d['userUid'] as String?) ?? '',
      name: (d['name'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      countryCode: (d['countryCode'] as String?) ?? '',
      status: _statusFrom(d['status'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: d['reviewedBy'] as String?,
    );
  }
}

class EventRegistrationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notifications = NotificationService();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('eventRegistrations');

  /// Submit a new registration request for an event. Deterministic doc id
  /// `{eventId}_{uid}` so a user can only have one in-flight request per event.
  Future<void> submit({
    required String eventId,
    required String eventTitle,
    required String name,
    required String email,
    required String phone,
    required String countryCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final docId = '${eventId}_${user.uid}';
    await _col.doc(docId).set({
      'eventId': eventId,
      'eventTitle': eventTitle,
      'userUid': user.uid,
      'name': name,
      'email': email,
      'phone': phone,
      'countryCode': countryCode,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewedBy': null,
    });
  }

  /// Stream of all pending registrations (admin view).
  Stream<List<EventRegistration>> streamPending() {
    return _col
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(EventRegistration.fromDoc).toList()
          ..sort((a, b) {
            final ac = a.createdAt;
            final bc = b.createdAt;
            if (ac == null) return 1;
            if (bc == null) return -1;
            return bc.compareTo(ac);
          }));
  }

  /// Pending registrations for a single event — shown in the group settings
  /// screen so the admin can approve/reject people who signed up for THIS
  /// event without leaving the chat.
  Stream<List<EventRegistration>> streamPendingForEvent(String eventId) {
    return _col
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(EventRegistration.fromDoc).toList()
          ..sort((a, b) {
            final ac = a.createdAt;
            final bc = b.createdAt;
            if (ac == null) return 1;
            if (bc == null) return -1;
            return bc.compareTo(ac);
          }));
  }

  /// Stream a single user's registration for a specific event (nullable).
  Stream<EventRegistration?> streamMine(String eventId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _col.doc('${eventId}_$uid').snapshots().map(
          (s) => s.exists ? EventRegistration.fromDoc(s) : null,
        );
  }

  /// Approve a registration: marks it approved, adds the user to the event
  /// chat's members subcollection, creates the event chat doc if missing,
  /// and notifies the user in-app.
  Future<void> approve(EventRegistration reg) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Not signed in');

    final chatRef = _db.collection('eventChats').doc(reg.eventId);
    final memberRef = chatRef.collection('members').doc(reg.userUid);

    final batch = _db.batch();
    batch.set(chatRef, {
      'eventId': reg.eventId,
      'eventTitle': reg.eventTitle,
      'adminUid': admin.uid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(memberRef, {
      'uid': reg.userUid,
      'name': reg.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_col.doc(reg.id), {
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': admin.uid,
    });
    await batch.commit();

    try {
      await _notifications.createNotification(
        targetUid: reg.userUid,
        type: 'event_approved',
        actorUid: admin.uid,
        targetId: reg.eventId,
      );
    } catch (_) {
      // best-effort
    }
  }

  /// Reject a registration: marks it rejected and notifies the user.
  Future<void> reject(EventRegistration reg) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Not signed in');

    await _col.doc(reg.id).update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': admin.uid,
    });

    try {
      await _notifications.createNotification(
        targetUid: reg.userUid,
        type: 'event_rejected',
        actorUid: admin.uid,
        targetId: reg.eventId,
      );
    } catch (_) {}
  }
}
