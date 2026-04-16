import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final String? imageUrl;
  final String? sharedPostId;
  final DateTime? createdAt;
  final List<String> seenBy;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    this.imageUrl,
    this.sharedPostId,
    this.createdAt,
    required this.seenBy,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      imageUrl: d['imageUrl'] as String?,
      sharedPostId: d['sharedPostId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      seenBy: List<String>.from(d['seenBy'] as List? ?? []),
    );
  }
}

class ChatConversation {
  final String chatId;
  final String otherUid;
  final String otherUsername;
  final String otherAvatarUrl;
  final String lastMessage;
  final DateTime? lastTime;
  final int unreadCount;

  /// true = the other person initiated and this user hasn't replied yet
  final bool isRequest;

  const ChatConversation({
    required this.chatId,
    required this.otherUid,
    required this.otherUsername,
    required this.otherAvatarUrl,
    required this.lastMessage,
    this.lastTime,
    required this.unreadCount,
    required this.isRequest,
  });

  factory ChatConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String currentUid,
  ) {
    final d = doc.data() ?? {};
    final participants = List<String>.from(d['participants'] as List? ?? []);
    final otherUid = participants.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );
    final userData = (d['userData'] as Map<String, dynamic>?) ?? {};
    final otherData = (userData[otherUid] as Map<String, dynamic>?) ?? {};
    final acceptedBy = List<String>.from(d['acceptedBy'] as List? ?? []);
    final unread = (d['unread'] as Map<String, dynamic>?) ?? {};

    return ChatConversation(
      chatId: doc.id,
      otherUid: otherUid,
      otherUsername: (otherData['username'] as String?) ?? 'User',
      otherAvatarUrl: (otherData['avatarUrl'] as String?) ?? '',
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastTime: (d['lastTime'] as Timestamp?)?.toDate(),
      unreadCount: (unread[currentUid] as int?) ?? 0,
      isRequest: !acceptedBy.contains(currentUid),
    );
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _chatDoc(String chatId) =>
      _db.collection('chats').doc(chatId);

  CollectionReference<Map<String, dynamic>> _messagesCol(String chatId) =>
      _chatDoc(chatId).collection('messages');

  /// Deterministic chat ID from two user IDs.
  String buildChatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Creates or retrieves the chat document between two users.
  /// Returns the chatId.
  Future<String> openChat({
    required String currentUid,
    required String otherUid,
  }) async {
    final id = buildChatId(currentUid, otherUid);
    final snap = await _chatDoc(id).get();

    if (!snap.exists) {
      // Fetch both users' display data for denormalization.
      final currentSnap = await _db.collection('users').doc(currentUid).get();
      final otherSnap = await _db.collection('users').doc(otherUid).get();
      final cu = currentSnap.data() ?? {};
      final ou = otherSnap.data() ?? {};

      await _chatDoc(id).set({
        'participants': [currentUid, otherUid],
        'userData': {
          currentUid: {
            'username': cu['username'] ?? '',
            'avatarUrl': cu['avatarUrl'] ?? '',
          },
          otherUid: {
            'username': ou['username'] ?? '',
            'avatarUrl': ou['avatarUrl'] ?? '',
          },
        },
        'lastMessage': '',
        'lastMessageSenderUid': '',
        'lastTime': FieldValue.serverTimestamp(),
        'unread': {currentUid: 0, otherUid: 0},
        // Only the initiator has accepted; receiver sees it as a request.
        'acceptedBy': [currentUid],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return id;
  }

  /// Sends a text message and updates the chat summary atomically.
  Future<void> sendMessage({
    required String chatId,
    required String senderUid,
    required String receiverUid,
    required String text,
    String? imageUrl,
  }) async {
    final trimmedText = text.trim();
    final normalizedImageUrl = imageUrl?.trim();
    if (trimmedText.isEmpty &&
        (normalizedImageUrl == null || normalizedImageUrl.isEmpty)) {
      return;
    }

    final batch = _db.batch();
    final msgRef = _messagesCol(chatId).doc();
    final chatRef = _chatDoc(chatId);
    final lastMessage = trimmedText.isNotEmpty
        ? trimmedText
        : (normalizedImageUrl?.isNotEmpty ?? false)
            ? 'Sent a photo'
            : '';

    batch.set(msgRef, {
      'senderUid': senderUid,
      'receiverUid': receiverUid,
      'text': trimmedText,
      'imageUrl': normalizedImageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [senderUid],
    });
    batch.set(
      chatRef,
      {
        'lastMessage': lastMessage,
        'lastMessageSenderUid': senderUid,
        'lastTime': FieldValue.serverTimestamp(),
        'acceptedBy': FieldValue.arrayUnion([senderUid]),
        'unread.$receiverUid': FieldValue.increment(1),
        'unread.$senderUid': 0,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// Resets the unread counter for [uid] in [chatId].
  Future<void> markSeen({
    required String chatId,
    required String uid,
  }) async {
    await _chatDoc(chatId).update({'unread.$uid': 0});
  }

  /// Real-time stream of messages, oldest first.
  Stream<List<ChatMessage>> streamMessages(String chatId) {
    return _messagesCol(chatId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  /// Real-time stream of all conversations for [uid], sorted by latest message.
  Stream<List<ChatConversation>> streamInbox(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((s) {
      final convs =
          s.docs.map((doc) => ChatConversation.fromDoc(doc, uid)).toList();
      // Sort in Dart to avoid requiring a Firestore composite index.
      convs.sort((a, b) {
        if (a.lastTime == null) return 1;
        if (b.lastTime == null) return -1;
        return b.lastTime!.compareTo(a.lastTime!);
      });
      return convs;
    });
  }

  Stream<List<ChatConversation>> streamRequests(String uid) {
    return streamInbox(uid).map(
      (conversations) => conversations
          .where((conversation) => conversation.isRequest)
          .toList(),
    );
  }

  Stream<List<ChatConversation>> streamAcceptedInbox(String uid) {
    return streamInbox(uid).map(
      (conversations) => conversations
          .where((conversation) => !conversation.isRequest)
          .toList(),
    );
  }
}
