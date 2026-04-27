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
  final String? voiceUrl;
  final int? voiceDurationMs;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderUid;
  final DateTime? createdAt;
  final List<String> seenBy;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    this.imageUrl,
    this.sharedPostId,
    this.voiceUrl,
    this.voiceDurationMs,
    this.replyToId,
    this.replyToText,
    this.replyToSenderUid,
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
      voiceUrl: d['voiceUrl'] as String?,
      voiceDurationMs: (d['voiceDurationMs'] as num?)?.toInt(),
      replyToId: d['replyToId'] as String?,
      replyToText: d['replyToText'] as String?,
      replyToSenderUid: d['replyToSenderUid'] as String?,
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

  // Group-chat additions
  final bool isGroup;
  final String groupName;
  final String groupAvatarUrl;
  final String adminUid;
  final List<String> participants;

  const ChatConversation({
    required this.chatId,
    required this.otherUid,
    required this.otherUsername,
    required this.otherAvatarUrl,
    required this.lastMessage,
    this.lastTime,
    required this.unreadCount,
    required this.isRequest,
    this.isGroup = false,
    this.groupName = '',
    this.groupAvatarUrl = '',
    this.adminUid = '',
    this.participants = const [],
  });

  factory ChatConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String currentUid,
  ) {
    final d = doc.data() ?? {};
    final participants = List<String>.from(d['participants'] as List? ?? []);
    final kind = (d['kind'] as String?) ?? 'direct';
    final isGroup = kind == 'group';
    final userData = (d['userData'] as Map<String, dynamic>?) ?? {};
    final acceptedBy = List<String>.from(d['acceptedBy'] as List? ?? []);
    final unread = (d['unread'] as Map<String, dynamic>?) ?? {};

    String otherUid = '';
    String otherUsername = 'User';
    String otherAvatarUrl = '';

    if (!isGroup) {
      otherUid = participants.firstWhere(
        (uid) => uid != currentUid,
        orElse: () => '',
      );
      final otherData = (userData[otherUid] as Map<String, dynamic>?) ?? {};
      otherUsername = (otherData['username'] as String?) ?? 'User';
      otherAvatarUrl = (otherData['avatarUrl'] as String?) ?? '';
    }

    return ChatConversation(
      chatId: doc.id,
      otherUid: otherUid,
      otherUsername: otherUsername,
      otherAvatarUrl: otherAvatarUrl,
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastTime: (d['lastTime'] as Timestamp?)?.toDate(),
      unreadCount: (unread[currentUid] as int?) ?? 0,
      // Groups are always "accepted" since you explicitly opted in.
      isRequest: !isGroup && !acceptedBy.contains(currentUid),
      isGroup: isGroup,
      groupName: (d['groupName'] as String?) ?? '',
      groupAvatarUrl: (d['groupAvatarUrl'] as String?) ?? '',
      adminUid: (d['adminUid'] as String?) ?? '',
      participants: participants,
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
  /// Works for both 1:1 and group chats: if the chat has more than 2
  /// participants, unread counters are incremented for every recipient.
  Future<void> sendMessage({
    required String chatId,
    required String senderUid,
    required String receiverUid,
    required String text,
    String? imageUrl,
    String? sharedPostId,
    String? voiceUrl,
    int? voiceDurationMs,
    String? replyToId,
    String? replyToText,
    String? replyToSenderUid,
  }) async {
    final trimmedText = text.trim();
    final normalizedImageUrl = imageUrl?.trim();
    final normalizedSharedPostId = sharedPostId?.trim();
    final normalizedVoiceUrl = voiceUrl?.trim();
    final hasSharedPost =
        normalizedSharedPostId != null && normalizedSharedPostId.isNotEmpty;
    final hasVoice =
        normalizedVoiceUrl != null && normalizedVoiceUrl.isNotEmpty;
    if (trimmedText.isEmpty &&
        (normalizedImageUrl == null || normalizedImageUrl.isEmpty) &&
        !hasSharedPost &&
        !hasVoice) {
      return;
    }

    // Determine recipients for unread bookkeeping. For 1:1 we use the
    // receiverUid passed in. For groups we read participants from the
    // chat doc so every other member's unread count bumps.
    final chatSnap = await _chatDoc(chatId).get();
    final chatData = chatSnap.data() ?? {};
    final isGroup = (chatData['kind'] as String?) == 'group';
    final recipients = isGroup
        ? ((chatData['participants'] as List?)?.cast<String>() ?? const [])
            .where((u) => u != senderUid)
            .toList()
        : <String>[receiverUid];

    final batch = _db.batch();
    final msgRef = _messagesCol(chatId).doc();
    final chatRef = _chatDoc(chatId);
    final lastMessage = trimmedText.isNotEmpty
        ? trimmedText
        : hasSharedPost
            ? 'Shared a post'
            : hasVoice
                ? 'Voice message'
                : (normalizedImageUrl?.isNotEmpty ?? false)
                    ? 'Sent a photo'
                    : '';

    batch.set(msgRef, {
      'senderUid': senderUid,
      if (!isGroup) 'receiverUid': receiverUid,
      'text': trimmedText,
      'imageUrl': normalizedImageUrl,
      if (hasSharedPost) 'sharedPostId': normalizedSharedPostId,
      if (hasVoice) 'voiceUrl': normalizedVoiceUrl,
      if (hasVoice && voiceDurationMs != null)
        'voiceDurationMs': voiceDurationMs,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      if (replyToText != null && replyToText.isNotEmpty)
        'replyToText': replyToText,
      if (replyToSenderUid != null && replyToSenderUid.isNotEmpty)
        'replyToSenderUid': replyToSenderUid,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [senderUid],
    });

    final summary = <String, Object?>{
      'lastMessage': lastMessage,
      'lastMessageSenderUid': senderUid,
      'lastTime': FieldValue.serverTimestamp(),
      'acceptedBy': FieldValue.arrayUnion([senderUid]),
      'unread.$senderUid': 0,
    };
    for (final uid in recipients) {
      if (uid.isEmpty) continue;
      summary['unread.$uid'] = FieldValue.increment(1);
    }
    batch.set(chatRef, summary, SetOptions(merge: true));

    await batch.commit();
  }

  /// Resets the unread counter for [uid] in [chatId] AND marks every
  /// recent unseen message as seen by [uid] so the sender's double-check
  /// indicator can flip from "delivered" to "seen". We scan only the last
  /// 50 messages to bound cost — older history is left alone (a chat
  /// that's been open this long is realistically already seen anyway).
  Future<void> markSeen({
    required String chatId,
    required String uid,
  }) async {
    await _chatDoc(chatId).update({'unread.$uid': 0});

    final recent = await _messagesCol(chatId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final batch = _db.batch();
    var pending = 0;
    for (final doc in recent.docs) {
      final data = doc.data();
      final senderUid = data['senderUid'] as String? ?? '';
      if (senderUid == uid) continue; // own message, already in seenBy
      final seenBy = List<String>.from(data['seenBy'] as List? ?? []);
      if (seenBy.contains(uid)) continue;
      batch.update(doc.reference, {
        'seenBy': FieldValue.arrayUnion([uid]),
      });
      pending++;
    }
    if (pending > 0) {
      await batch.commit();
    }
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

  /// Create a multi-party group chat. [creatorUid] becomes the group admin.
  Future<String> createGroup({
    required String creatorUid,
    required List<String> memberUids,
    required String groupName,
    String? groupAvatarUrl,
  }) async {
    final ids = <String>{creatorUid, ...memberUids}.toList();
    if (ids.length < 2) throw Exception('Need at least 2 participants');
    if (groupName.trim().isEmpty) throw Exception('Group name required');

    // Denormalize each participant's display info.
    final userDataEntries = await Future.wait(
      ids.map((uid) async {
        final snap = await _db.collection('users').doc(uid).get();
        final d = snap.data() ?? {};
        return MapEntry(uid, {
          'username': d['username'] ?? '',
          'avatarUrl': d['avatarUrl'] ?? '',
        });
      }),
    );

    final ref = await _db.collection('chats').add({
      'kind': 'group',
      'participants': ids,
      'userData': Map.fromEntries(userDataEntries),
      'adminUid': creatorUid,
      'groupName': groupName.trim(),
      'groupAvatarUrl': groupAvatarUrl ?? '',
      'lastMessage': '',
      'lastMessageSenderUid': '',
      'lastTime': FieldValue.serverTimestamp(),
      'unread': {for (final id in ids) id: 0},
      // Everyone who's invited has already "accepted" (no request gate).
      'acceptedBy': ids,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Admin-only: add a new member to an existing group.
  Future<void> addGroupMember({
    required String chatId,
    required String uid,
  }) async {
    final snap = await _db.collection('users').doc(uid).get();
    final d = snap.data() ?? {};
    await _chatDoc(chatId).update({
      'participants': FieldValue.arrayUnion([uid]),
      'acceptedBy': FieldValue.arrayUnion([uid]),
      'userData.$uid': {
        'username': d['username'] ?? '',
        'avatarUrl': d['avatarUrl'] ?? '',
      },
      'unread.$uid': 0,
    });
  }

  /// Admin can remove anyone; anyone can remove themselves (leave).
  Future<void> leaveOrRemoveGroupMember({
    required String chatId,
    required String uid,
  }) async {
    await _chatDoc(chatId).update({
      'participants': FieldValue.arrayRemove([uid]),
      'acceptedBy': FieldValue.arrayRemove([uid]),
    });
  }

  /// Admin can rename. Enforced in Firestore rules.
  Future<void> renameGroup({
    required String chatId,
    required String name,
  }) async {
    await _chatDoc(chatId).update({'groupName': name.trim()});
  }
}
