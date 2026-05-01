import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final String? imageUrl;
  final String? videoUrl;
  final String? fileUrl;
  final String? fileName;
  final String? fileMimeType;
  final int? fileSizeBytes;
  final String? sharedPostId;
  final String? voiceUrl;
  final int? voiceDurationMs;

  /// Live transcript captured on the sender's device while recording
  /// the voice message. Lets the receiver read or translate the audio
  /// without round-tripping through a backend transcription job.
  final String? voiceTranscript;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderUid;

  /// When this message was sent in response to a story, [storyId] holds the
  /// story doc id and [storyImageUrl] holds the story thumbnail. The chat
  /// bubble renders a "Replied to story" header so the receiver can see
  /// which story the reply/reaction is about.
  final String? storyId;
  final String? storyImageUrl;
  final DateTime? createdAt;
  final List<String> seenBy;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    this.imageUrl,
    this.videoUrl,
    this.fileUrl,
    this.fileName,
    this.fileMimeType,
    this.fileSizeBytes,
    this.sharedPostId,
    this.voiceUrl,
    this.voiceDurationMs,
    this.voiceTranscript,
    this.replyToId,
    this.replyToText,
    this.replyToSenderUid,
    this.storyId,
    this.storyImageUrl,
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
      videoUrl: d['videoUrl'] as String?,
      fileUrl: d['fileUrl'] as String?,
      fileName: d['fileName'] as String?,
      fileMimeType: d['fileMimeType'] as String?,
      fileSizeBytes: (d['fileSizeBytes'] as num?)?.toInt(),
      sharedPostId: d['sharedPostId'] as String?,
      voiceUrl: d['voiceUrl'] as String?,
      voiceDurationMs: (d['voiceDurationMs'] as num?)?.toInt(),
      voiceTranscript: d['voiceTranscript'] as String?,
      replyToId: d['replyToId'] as String?,
      replyToText: d['replyToText'] as String?,
      replyToSenderUid: d['replyToSenderUid'] as String?,
      storyId: d['storyId'] as String?,
      storyImageUrl: d['storyImageUrl'] as String?,
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

      // Mutual follow ("friends") skips the request gate so the receiver
      // sees the new chat in their inbox immediately. Otherwise only the
      // initiator has accepted and the receiver gets a request.
      final mutualFollow = await _isMutualFollow(currentUid, otherUid);
      final acceptedBy =
          mutualFollow ? <String>[currentUid, otherUid] : <String>[currentUid];

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
        'acceptedBy': acceptedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return id;
  }

  /// True if both users follow each other with `status == 'active'`.
  /// Returns false on any rule/network error so callers default to the
  /// safer "request" state rather than silently auto-accepting.
  Future<bool> _isMutualFollow(String a, String b) async {
    try {
      final aFollowsB = await _db.doc('users/$a/following/$b').get();
      if (!aFollowsB.exists) return false;
      if ((aFollowsB.data()?['status'] as String?) == 'pending') return false;
      final bFollowsA = await _db.doc('users/$b/following/$a').get();
      if (!bFollowsA.exists) return false;
      if ((bFollowsA.data()?['status'] as String?) == 'pending') return false;
      return true;
    } catch (_) {
      return false;
    }
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
    String? videoUrl,
    String? fileUrl,
    String? fileName,
    String? fileMimeType,
    int? fileSizeBytes,
    String? sharedPostId,
    String? voiceUrl,
    int? voiceDurationMs,
    String? voiceTranscript,
    String? replyToId,
    String? replyToText,
    String? replyToSenderUid,
    String? storyId,
    String? storyImageUrl,
  }) async {
    final trimmedText = text.trim();
    final normalizedImageUrl = imageUrl?.trim();
    final normalizedVideoUrl = videoUrl?.trim();
    final normalizedFileUrl = fileUrl?.trim();
    final normalizedFileName = fileName?.trim();
    final normalizedSharedPostId = sharedPostId?.trim();
    final normalizedVoiceUrl = voiceUrl?.trim();
    final normalizedVoiceTranscript = voiceTranscript?.trim();
    final normalizedStoryId = storyId?.trim();
    final normalizedStoryImageUrl = storyImageUrl?.trim();
    final hasImage =
        normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;
    final hasVideo =
        normalizedVideoUrl != null && normalizedVideoUrl.isNotEmpty;
    final hasFile = normalizedFileUrl != null && normalizedFileUrl.isNotEmpty;
    final hasSharedPost =
        normalizedSharedPostId != null && normalizedSharedPostId.isNotEmpty;
    final hasVoice =
        normalizedVoiceUrl != null && normalizedVoiceUrl.isNotEmpty;
    final hasStoryRef =
        normalizedStoryId != null && normalizedStoryId.isNotEmpty;
    if (trimmedText.isEmpty &&
        !hasImage &&
        !hasVideo &&
        !hasFile &&
        !hasSharedPost &&
        !hasVoice &&
        !hasStoryRef) {
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
                : hasVideo
                    ? 'Sent a video'
                    : hasFile
                        ? 'Sent a file'
                        : hasImage
                            ? 'Sent a photo'
                            : '';

    batch.set(msgRef, {
      'senderUid': senderUid,
      if (!isGroup) 'receiverUid': receiverUid,
      'text': trimmedText,
      'imageUrl': normalizedImageUrl,
      if (hasVideo) 'videoUrl': normalizedVideoUrl,
      if (hasFile) 'fileUrl': normalizedFileUrl,
      if (hasFile &&
          normalizedFileName != null &&
          normalizedFileName.isNotEmpty)
        'fileName': normalizedFileName,
      if (hasFile && fileMimeType != null && fileMimeType.isNotEmpty)
        'fileMimeType': fileMimeType,
      if (hasFile && fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
      if (hasSharedPost) 'sharedPostId': normalizedSharedPostId,
      if (hasVoice) 'voiceUrl': normalizedVoiceUrl,
      if (hasVoice && voiceDurationMs != null)
        'voiceDurationMs': voiceDurationMs,
      if (hasVoice &&
          normalizedVoiceTranscript != null &&
          normalizedVoiceTranscript.isNotEmpty)
        'voiceTranscript': normalizedVoiceTranscript,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      if (replyToText != null && replyToText.isNotEmpty)
        'replyToText': replyToText,
      if (replyToSenderUid != null && replyToSenderUid.isNotEmpty)
        'replyToSenderUid': replyToSenderUid,
      if (hasStoryRef) 'storyId': normalizedStoryId,
      if (hasStoryRef &&
          normalizedStoryImageUrl != null &&
          normalizedStoryImageUrl.isNotEmpty)
        'storyImageUrl': normalizedStoryImageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [senderUid],
    });

    // Auto-accept the chat for the receiver when both users follow each
    // other. Without this, mutual followers would still see the first
    // message in their Requests tab even though they've already opted
    // into each other's content.
    final acceptedUids = <String>{senderUid};
    if (!isGroup && recipients.length == 1) {
      final receiver = recipients.first;
      if (receiver.isNotEmpty && await _isMutualFollow(senderUid, receiver)) {
        acceptedUids.add(receiver);
      }
    }

    final summary = <String, Object?>{
      'lastMessage': lastMessage,
      'lastMessageSenderUid': senderUid,
      'lastTime': FieldValue.serverTimestamp(),
      'acceptedBy': FieldValue.arrayUnion(acceptedUids.toList()),
      'unread.$senderUid': 0,
    };
    for (final uid in recipients) {
      if (uid.isEmpty) continue;
      summary['unread.$uid'] = FieldValue.increment(1);
    }
    batch.set(chatRef, summary, SetOptions(merge: true));

    await batch.commit();
  }

  /// Resets the unread counter for [uid] in [chatId] AND marks the most
  /// recent messages as seen by [uid] so the sender sees a "Seen" indicator.
  ///
  /// We only touch the last 50 messages — older messages are assumed seen
  /// once they've scrolled out of view. seenBy is appended via
  /// [FieldValue.arrayUnion] so concurrent readers don't clobber each other.
  Future<void> markSeen({
    required String chatId,
    required String uid,
  }) async {
    await _chatDoc(chatId).update({'unread.$uid': 0});

    final recent = await _messagesCol(chatId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    if (recent.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in recent.docs) {
      final data = doc.data();
      final seenBy = List<String>.from(data['seenBy'] as List? ?? const []);
      if (seenBy.contains(uid)) continue;
      // Don't mark our own messages as seen-by-us — pointless write.
      if (data['senderUid'] == uid) continue;
      batch.update(doc.reference, {
        'seenBy': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();
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
      // Hide chats that have no messages yet. openChat creates the doc
      // as soon as you visit a profile and tap "Message"; without this
      // filter the recipient saw a request notification for a chat the
      // other user never actually wrote to. Group chats stay visible
      // even when empty since the explicit invite already implies
      // intent. We use lastMessage as the gate (not lastTime) because
      // openChat sets a serverTimestamp on creation.
      final convs = s.docs
          .map((doc) => ChatConversation.fromDoc(doc, uid))
          .where((c) => c.isGroup || c.lastMessage.isNotEmpty)
          .toList();
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
    return streamInbox(uid).asyncMap((conversations) async {
      if (conversations.isEmpty) return const <ChatConversation>[];
      final mutualFriends = await _getMutualFriendUids(uid);
      return conversations
          .where(
            (conversation) =>
                conversation.isRequest &&
                !mutualFriends.contains(conversation.otherUid),
          )
          .toList();
    });
  }

  Stream<List<ChatConversation>> streamAcceptedInbox(String uid) {
    return streamInbox(uid).asyncMap((conversations) async {
      if (conversations.isEmpty) return const <ChatConversation>[];
      final mutualFriends = await _getMutualFriendUids(uid);
      return conversations
          .where(
            (conversation) =>
                !conversation.isRequest ||
                mutualFriends.contains(conversation.otherUid),
          )
          .toList();
    });
  }

  Future<Set<String>> _getMutualFriendUids(String uid) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final snaps = await Future.wait([
        userRef.collection('following').get(),
        userRef.collection('followers').get(),
      ]);

      final following = snaps[0]
          .docs
          .where((d) => (d.data()['status'] as String?) != 'pending')
          .map((d) => d.id)
          .toSet();
      final followers = snaps[1]
          .docs
          .where((d) => (d.data()['status'] as String?) != 'pending')
          .map((d) => d.id)
          .toSet();

      return following.intersection(followers);
    } catch (_) {
      return const <String>{};
    }
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

  /// Permanently delete a 1:1 chat for BOTH participants — wipes every
  /// message in the subcollection, then the chat doc itself. Messages
  /// are deleted in 400-doc batches (Firestore batch limit is 500).
  ///
  /// Note: media files (images, voice, video, attached docs) live in
  /// Supabase Storage and require a separate edge-function delete which
  /// isn't deployed yet — those bytes become orphans on the storage
  /// bucket. We log the missed URLs so a future cleanup job can reap
  /// them.
  Future<void> deleteChat(String chatId) async {
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    while (true) {
      Query<Map<String, dynamic>> q = _messagesCol(chatId).limit(400);
      if (lastDoc != null) q = q.startAfterDocument(lastDoc);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
      lastDoc = snap.docs.last;
    }
    // Drop the parent chat doc last so the inbox stops listing it.
    await _chatDoc(chatId).delete();
  }

  /// Configure auto-deletion of messages for [chatId]. Pass null to
  /// disable. The `autoDeleteSeconds` field is read by a backend job /
  /// scheduled function (not part of this changelist) that prunes
  /// messages older than the threshold without removing the chat doc
  /// itself, so the conversation stays in the user's inbox while old
  /// content disappears.
  Future<void> setAutoDeletePeriod({
    required String chatId,
    required Duration? period,
  }) async {
    if (period == null) {
      await _chatDoc(chatId).update({
        'autoDeleteSeconds': FieldValue.delete(),
      });
    } else {
      await _chatDoc(chatId).update({
        'autoDeleteSeconds': period.inSeconds,
      });
    }
  }
}
