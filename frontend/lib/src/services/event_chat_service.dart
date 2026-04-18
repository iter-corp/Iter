import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// Stream every event chat doc the user is a member of. Combines two
  /// queries: (a) chats where the user is admin, (b) chats that contain
  /// a member doc for this user. The function collects them into one list.
  Stream<List<EventChatSummary>> streamMyEventChats(String uid) {
    // We piggyback on the `collectionGroup` of members to find every event the
    // user belongs to, then fetch each parent chat doc.
    return _db
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .asyncMap((memberSnap) async {
      // Collect parent event ids from member docs.
      final eventIds = <String>{};
      final lastSeenByEvent = <String, DateTime?>{};
      for (final m in memberSnap.docs) {
        final parent = m.reference.parent.parent;
        if (parent == null) continue;
        // Ensure the grandparent is 'eventChats'.
        if (parent.parent.id != 'eventChats') continue;
        eventIds.add(parent.id);
        lastSeenByEvent[parent.id] =
            (m.data()['lastSeenAt'] as Timestamp?)?.toDate();
      }

      if (eventIds.isEmpty) return <EventChatSummary>[];

      // Fetch each chat doc in parallel.
      final docs = await Future.wait(
        eventIds.map((id) => _chatDoc(id).get()),
      );

      final result = <EventChatSummary>[];
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
}
