import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class EventChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final String? imageUrl;
  final DateTime? createdAt;

  const EventChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    this.imageUrl,
    this.createdAt,
  });

  factory EventChatMessage.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return EventChatMessage(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      imageUrl: d['imageUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class EventChatSummary {
  final String eventId;
  final String eventTitle;
  final String adminUid;
  final String lastMessage;
  final DateTime? lastTime;
  final int unreadCount;

  const EventChatSummary({
    required this.eventId,
    required this.eventTitle,
    required this.adminUid,
    required this.lastMessage,
    required this.lastTime,
    required this.unreadCount,
  });
}

class EventChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notifications = NotificationService();

  DocumentReference<Map<String, dynamic>> _chatDoc(String eventId) =>
      _db.collection('eventChats').doc(eventId);

  CollectionReference<Map<String, dynamic>> _messagesCol(String eventId) =>
      _chatDoc(eventId).collection('messages');

  CollectionReference<Map<String, dynamic>> _membersCol(String eventId) =>
      _chatDoc(eventId).collection('members');

  /// Admin-only write: post a message to the event's group chat and
  /// update the chat summary for sorting in the inbox list.
  Future<void> sendMessage({
    required String eventId,
    required String text,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final trimmed = text.trim();
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    final batch = _db.batch();
    final msgRef = _messagesCol(eventId).doc();
    final preview = trimmed.isNotEmpty ? trimmed : 'Sent a photo';

    batch.set(msgRef, {
      'senderUid': user.uid,
      'text': trimmed,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _chatDoc(eventId),
      {
        'lastMessage': preview,
        'lastMessageSenderUid': user.uid,
        'lastTime': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Messages stream (oldest first).
  Stream<List<EventChatMessage>> streamMessages(String eventId) {
    return _messagesCol(eventId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(EventChatMessage.fromDoc).toList());
  }

  /// Stream every event chat doc the user is a member of, plus every chat
  /// where the user is the admin (even if they haven't added themselves as
  /// a member). Combines:
  ///   (a) chats referenced via the user's `members` docs (collectionGroup),
  ///   (b) chats where `adminUid == uid` (admin's own chats, shown as soon
  ///       as an event is created — before any members join).
  Stream<List<EventChatSummary>> streamMyEventChats(String uid) {
    final memberEventsStream = _db
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .snapshots();
    final adminEventsStream = _db
        .collection('eventChats')
        .where('adminUid', isEqualTo: uid)
        .snapshots();

    // Combine both streams. We re-emit whenever either side changes.
    return _combineLatest2(memberEventsStream, adminEventsStream)
        .asyncMap((pair) async {
      final memberSnap = pair.$1;
      final adminSnap = pair.$2;

      final eventIds = <String>{};
      final lastSeenByEvent = <String, DateTime?>{};

      // From membership docs.
      for (final m in memberSnap.docs) {
        final parent = m.reference.parent.parent;
        if (parent == null) continue;
        if (parent.parent.id != 'eventChats') continue;
        eventIds.add(parent.id);
        lastSeenByEvent[parent.id] =
            (m.data()['lastSeenAt'] as Timestamp?)?.toDate();
      }

      // Pre-seed admin-owned chat summaries (they're already fresh in
      // adminSnap so we don't need to re-fetch them below).
      final adminSummaries = <String, EventChatSummary>{};
      for (final doc in adminSnap.docs) {
        eventIds.add(doc.id);
        final d = doc.data();
        final lastTime = (d['lastTime'] as Timestamp?)?.toDate();
        adminSummaries[doc.id] = EventChatSummary(
          eventId: doc.id,
          eventTitle: (d['eventTitle'] as String?) ?? 'Event',
          adminUid: (d['adminUid'] as String?) ?? '',
          lastMessage: (d['lastMessage'] as String?) ?? '',
          lastTime: lastTime,
          unreadCount: 0, // admin is always caught up on their own chat
        );
      }

      if (eventIds.isEmpty) return <EventChatSummary>[];

      // Fetch any chat docs we haven't already got.
      final missing = eventIds.where((id) => !adminSummaries.containsKey(id));
      final docs = await Future.wait(missing.map((id) => _chatDoc(id).get()));

      final result = <EventChatSummary>[...adminSummaries.values];
      for (final doc in docs) {
        if (!doc.exists) continue;
        final d = doc.data() ?? {};
        final lastTime = (d['lastTime'] as Timestamp?)?.toDate();
        final lastSeen = lastSeenByEvent[doc.id];
        final unread =
            (lastTime != null && lastSeen != null && lastTime.isAfter(lastSeen))
                ? 1
                : (lastTime != null && lastSeen == null)
                    ? 1
                    : 0;

        result.add(EventChatSummary(
          eventId: doc.id,
          eventTitle: (d['eventTitle'] as String?) ?? 'Event',
          adminUid: (d['adminUid'] as String?) ?? '',
          lastMessage: (d['lastMessage'] as String?) ?? '',
          lastTime: lastTime,
          unreadCount: unread,
        ));
      }

      result.sort((a, b) {
        if (a.lastTime == null) return 1;
        if (b.lastTime == null) return -1;
        return b.lastTime!.compareTo(a.lastTime!);
      });
      return result;
    });
  }

  /// Minimal combine-latest for two streams — emits `(a, b)` tuples whenever
  /// either upstream emits, once both have produced at least one value.
  Stream<(A, B)> _combineLatest2<A, B>(Stream<A> a, Stream<B> b) async* {
    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;
    final controller = StreamController<(A, B)>();

    final subA = a.listen((v) {
      lastA = v;
      hasA = true;
      if (hasB) controller.add((lastA as A, lastB as B));
    }, onError: controller.addError);
    final subB = b.listen((v) {
      lastB = v;
      hasB = true;
      if (hasA) controller.add((lastA as A, lastB as B));
    }, onError: controller.addError);

    try {
      yield* controller.stream;
    } finally {
      await subA.cancel();
      await subB.cancel();
      await controller.close();
    }
  }

  /// Mark the user as having seen the chat up to now.
  Future<void> markSeen(String eventId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _membersCol(eventId)
        .doc(user.uid)
        .set({'lastSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  /// Stream the admin uid for an event chat (used by UI to toggle compose).
  Stream<String?> streamAdminUid(String eventId) {
    return _chatDoc(eventId)
        .snapshots()
        .map((s) => s.data()?['adminUid'] as String?);
  }

  /// Stream the list of members in an event chat (used for "see admin", etc.).
  Stream<List<Map<String, dynamic>>> streamMembers(String eventId) {
    return _membersCol(eventId).snapshots().map(
          (s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList(),
        );
  }

  /// Admin-only: add a user directly to the event chat (skipping the
  /// registration flow) and notify them so they can choose to stay or leave.
  Future<void> addMember({
    required String eventId,
    required String uid,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Not signed in');

    final userSnap = await _db.collection('users').doc(uid).get();
    final name = (userSnap.data()?['username'] as String?) ?? '';

    await _membersCol(eventId).doc(uid).set({
      'uid': uid,
      'name': name,
      'joinedAt': FieldValue.serverTimestamp(),
      'addedByAdmin': true,
    }, SetOptions(merge: true));

    try {
      await _notifications.createNotification(
        targetUid: uid,
        type: 'event_invited',
        actorUid: admin.uid,
        targetId: eventId,
      );
    } catch (_) {
      // best-effort
    }
  }

  /// Remove a member. Admin can remove anyone; a user can remove themselves
  /// (i.e. "leave the group"). Mirrors the Firestore rule:
  ///   allow delete: if isSelf(uid) || isAdmin();
  Future<void> removeMember({
    required String eventId,
    required String uid,
    bool notifyRemovedUser = true,
  }) async {
    final current = _auth.currentUser;
    if (current == null) throw Exception('Not signed in');

    await _membersCol(eventId).doc(uid).delete();

    // If the admin kicked someone, tell them.
    if (notifyRemovedUser && current.uid != uid) {
      try {
        await _notifications.createNotification(
          targetUid: uid,
          type: 'event_removed',
          actorUid: current.uid,
          targetId: eventId,
        );
      } catch (_) {}
    }
  }

  /// Convenience wrapper — the current user leaves the group.
  Future<void> leaveGroup(String eventId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    await removeMember(
      eventId: eventId,
      uid: user.uid,
      notifyRemovedUser: false,
    );
  }
}
