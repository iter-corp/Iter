import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'e2ee/e2ee_service.dart';
import 'message_cache.dart';

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

  /// Sticker support — either a bundled asset path (starts with 'asset:') or
  /// a Firebase Storage URL for user-uploaded custom stickers.
  final String? stickerUrl;
  final String? stickerPackId;

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

  /// A shared location pin. When [locationLat] / [locationLng] are set the
  /// bubble renders a mini map preview with a "Directions" action.
  final double? locationLat;
  final double? locationLng;
  final String? locationLabel;

  final DateTime? createdAt;
  final List<String> seenBy;

  bool get hasLocation => locationLat != null && locationLng != null;

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
    this.stickerUrl,
    this.stickerPackId,
    this.replyToId,
    this.replyToText,
    this.replyToSenderUid,
    this.storyId,
    this.storyImageUrl,
    this.locationLat,
    this.locationLng,
    this.locationLabel,
    this.createdAt,
    required this.seenBy,
    this.encryptedUnreadable = false,
  });

  /// True if the original message was encrypted on the wire and could not
  /// be decrypted on this device. Used by the bubble UI to render a
  /// "🔒 Couldn't decrypt on this device" placeholder instead of empty
  /// text.
  final bool encryptedUnreadable;

  /// Builds a [ChatMessage] from a Firestore doc. When [decrypted] is
  /// supplied (the JSON payload of an `enc` envelope after decryption),
  /// its fields override the corresponding plaintext fields on the doc.
  /// Pass `decryptionFailed: true` if the doc had an `enc` envelope but
  /// this device couldn't decrypt it.
  factory ChatMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, dynamic>? decrypted,
    bool decryptionFailed = false,
  }) {
    final d = doc.data() ?? {};
    final loc = d['location'];
    final locMap = loc is Map ? loc : null;
    String pickStr(String fromDecKey, String fromDocKey) {
      final v = decrypted?[fromDecKey];
      if (v is String && v.isNotEmpty) return v;
      return (d[fromDocKey] as String?) ?? '';
    }

    String? pickOptStr(String fromDecKey, String fromDocKey) {
      final v = decrypted?[fromDecKey];
      if (v is String && v.isNotEmpty) return v;
      return d[fromDocKey] as String?;
    }

    return ChatMessage(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      text: pickStr('t', 'text'),
      imageUrl: d['imageUrl'] as String?,
      videoUrl: d['videoUrl'] as String?,
      fileUrl: d['fileUrl'] as String?,
      fileName: pickOptStr('fn', 'fileName'),
      fileMimeType: d['fileMimeType'] as String?,
      fileSizeBytes: (d['fileSizeBytes'] as num?)?.toInt(),
      sharedPostId: d['sharedPostId'] as String?,
      voiceUrl: d['voiceUrl'] as String?,
      voiceDurationMs: (d['voiceDurationMs'] as num?)?.toInt(),
      voiceTranscript: pickOptStr('vt', 'voiceTranscript'),
      stickerUrl: d['stickerUrl'] as String?,
      stickerPackId: d['stickerPackId'] as String?,
      replyToId: d['replyToId'] as String?,
      replyToText: pickOptStr('rt', 'replyToText'),
      replyToSenderUid: d['replyToSenderUid'] as String?,
      storyId: d['storyId'] as String?,
      storyImageUrl: d['storyImageUrl'] as String?,
      locationLat: (locMap?['lat'] as num?)?.toDouble(),
      locationLng: (locMap?['lng'] as num?)?.toDouble(),
      locationLabel: pickOptStr('ll', 'locationLabel'),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      seenBy: List<String>.from(d['seenBy'] as List? ?? []),
      encryptedUnreadable: decryptionFailed,
    );
  }

  /// Serialize this message into a plain map suitable for the on-disk
  /// snapshot cache (see [MessageCache.saveSnapshot]). The format mirrors
  /// the Firestore doc shape closely enough that [fromCacheJson] can
  /// rebuild a [ChatMessage] without a [DocumentSnapshot].
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'senderUid': senderUid,
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (fileName != null) 'fileName': fileName,
        if (fileMimeType != null) 'fileMimeType': fileMimeType,
        if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
        if (sharedPostId != null) 'sharedPostId': sharedPostId,
        if (voiceUrl != null) 'voiceUrl': voiceUrl,
        if (voiceDurationMs != null) 'voiceDurationMs': voiceDurationMs,
        if (voiceTranscript != null) 'voiceTranscript': voiceTranscript,
        if (stickerUrl != null) 'stickerUrl': stickerUrl,
        if (stickerPackId != null) 'stickerPackId': stickerPackId,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToSenderUid != null) 'replyToSenderUid': replyToSenderUid,
        if (storyId != null) 'storyId': storyId,
        if (storyImageUrl != null) 'storyImageUrl': storyImageUrl,
        if (locationLat != null) 'locationLat': locationLat,
        if (locationLng != null) 'locationLng': locationLng,
        if (locationLabel != null) 'locationLabel': locationLabel,
        if (createdAt != null) 'createdAtMs': createdAt!.millisecondsSinceEpoch,
        'seenBy': seenBy,
      };

  /// Rebuild a [ChatMessage] from a [toCacheJson] map. The snapshot path
  /// is used for the synchronous first emission of [streamMessages] —
  /// once Firestore returns real docs, those replace cached entries.
  factory ChatMessage.fromCacheJson(Map<String, dynamic> m) => ChatMessage(
        id: (m['id'] as String?) ?? '',
        senderUid: (m['senderUid'] as String?) ?? '',
        text: (m['text'] as String?) ?? '',
        imageUrl: m['imageUrl'] as String?,
        videoUrl: m['videoUrl'] as String?,
        fileUrl: m['fileUrl'] as String?,
        fileName: m['fileName'] as String?,
        fileMimeType: m['fileMimeType'] as String?,
        fileSizeBytes: (m['fileSizeBytes'] as num?)?.toInt(),
        sharedPostId: m['sharedPostId'] as String?,
        voiceUrl: m['voiceUrl'] as String?,
        voiceDurationMs: (m['voiceDurationMs'] as num?)?.toInt(),
        voiceTranscript: m['voiceTranscript'] as String?,
        stickerUrl: m['stickerUrl'] as String?,
        stickerPackId: m['stickerPackId'] as String?,
        replyToId: m['replyToId'] as String?,
        replyToText: m['replyToText'] as String?,
        replyToSenderUid: m['replyToSenderUid'] as String?,
        storyId: m['storyId'] as String?,
        storyImageUrl: m['storyImageUrl'] as String?,
        locationLat: (m['locationLat'] as num?)?.toDouble(),
        locationLng: (m['locationLng'] as num?)?.toDouble(),
        locationLabel: m['locationLabel'] as String?,
        createdAt: (m['createdAtMs'] as num?) != null
            ? DateTime.fromMillisecondsSinceEpoch((m['createdAtMs'] as num).toInt())
            : null,
        seenBy: List<String>.from((m['seenBy'] as List?) ?? const []),
      );
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

  /// UIDs that have muted this chat. Read by the backend FCM dispatcher
  /// to skip sending push notifications to muted recipients.
  final List<String> mutedFor;

  // Group-chat additions
  final bool isGroup;
  final String groupName;
  final String groupAvatarUrl;
  final String adminUid;
  final List<String> participants;

  /// True when this chat is end-to-end encrypted (Telegram-style "secret
  /// chat"). Drives the lock icon in the inbox tile and the chat header,
  /// and is the user-visible expression of [ChatService._isSecretChat].
  final bool secret;

  const ChatConversation({
    required this.chatId,
    required this.otherUid,
    required this.otherUsername,
    required this.otherAvatarUrl,
    required this.lastMessage,
    this.lastTime,
    required this.unreadCount,
    required this.isRequest,
    this.mutedFor = const [],
    this.isGroup = false,
    this.groupName = '',
    this.groupAvatarUrl = '',
    this.adminUid = '',
    this.participants = const [],
    this.secret = false,
  });

  bool isMutedBy(String uid) => mutedFor.contains(uid);

  ChatConversation copyWith({
    String? chatId,
    String? otherUid,
    String? otherUsername,
    String? otherAvatarUrl,
    String? lastMessage,
    DateTime? lastTime,
    int? unreadCount,
    bool? isRequest,
    List<String>? mutedFor,
    bool? isGroup,
    String? groupName,
    String? groupAvatarUrl,
    String? adminUid,
    List<String>? participants,
    bool? secret,
  }) {
    return ChatConversation(
      chatId: chatId ?? this.chatId,
      otherUid: otherUid ?? this.otherUid,
      otherUsername: otherUsername ?? this.otherUsername,
      otherAvatarUrl: otherAvatarUrl ?? this.otherAvatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTime: lastTime ?? this.lastTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isRequest: isRequest ?? this.isRequest,
      mutedFor: mutedFor ?? this.mutedFor,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      groupAvatarUrl: groupAvatarUrl ?? this.groupAvatarUrl,
      adminUid: adminUid ?? this.adminUid,
      participants: participants ?? this.participants,
      secret: secret ?? this.secret,
    );
  }

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
    final unreadRaw = d['unread'];

    String otherUid = '';
    String otherUsername = 'User';
    String otherAvatarUrl = '';

    if (!isGroup) {
      otherUid = participants.firstWhere(
        (uid) => uid != currentUid,
        orElse: () => '',
      );
      // Backward-compat: older direct-chat docs may miss participants.
      if (otherUid.isEmpty && doc.id.contains('_')) {
        final ids = doc.id.split('_');
        if (ids.length == 2) {
          otherUid = ids.first == currentUid ? ids.last : ids.first;
        }
      }
      final otherData = (userData[otherUid] as Map<String, dynamic>?) ?? {};
      otherUsername = (otherData['username'] as String?) ?? 'User';
      otherAvatarUrl = (otherData['avatarUrl'] as String?) ?? '';
    }

    int unreadCount = 0;
    if (unreadRaw is Map) {
      final raw = unreadRaw[currentUid];
      if (raw is num) {
        unreadCount = raw.toInt();
      } else if (raw is String) {
        unreadCount = int.tryParse(raw) ?? 0;
      }
    }
    if (unreadCount < 0) unreadCount = 0;

    return ChatConversation(
      chatId: doc.id,
      otherUid: otherUid,
      otherUsername: otherUsername,
      otherAvatarUrl: otherAvatarUrl,
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastTime: (d['lastTime'] as Timestamp?)?.toDate(),
      unreadCount: unreadCount,
      // Groups are always "accepted" since you explicitly opted in.
      isRequest: !isGroup && !acceptedBy.contains(currentUid),
      mutedFor: List<String>.from(d['mutedFor'] as List? ?? const []),
      isGroup: isGroup,
      groupName: (d['groupName'] as String?) ?? '',
      groupAvatarUrl: (d['groupAvatarUrl'] as String?) ?? '',
      adminUid: (d['adminUid'] as String?) ?? '',
      participants: participants,
      secret: ChatService._isSecretChat(d),
    );
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class ChatService {
  ChatService({E2EEService? e2ee}) : _e2ee = e2ee ?? E2EEService();

  /// End-to-end encryption layer used for 1:1 chats. Group chats stay
  /// plaintext in v1 (event chats use a separate service).
  final E2EEService _e2ee;

  /// Plaintext placeholder shown anywhere the server might leak preview
  /// content (e.g. `lastMessage` for the inbox tile, or older clients
  /// that don't yet decrypt).
  static const String encryptedPreviewLabel = '🔒 Encrypted message';

  /// Permanently delete a group chat and all its messages. Admin only.
  Future<void> deleteGroup(String chatId) async {
    // For now, just call deleteChat. In future, add group-specific cleanup if needed.
    await deleteChat(chatId);
  }

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _chatDoc(String chatId) =>
      _db.collection('chats').doc(chatId);

  CollectionReference<Map<String, dynamic>> _messagesCol(String chatId) =>
      _chatDoc(chatId).collection('messages');

  bool _isDeletedForEveryone(Map<String, dynamic> data) =>
      data['deletedForEveryone'] == true;

  bool _isDeletedForUser(Map<String, dynamic> data, String uid) {
    final hidden = List<String>.from(
      data['deletedForUids'] as List? ?? const [],
    );
    return hidden.contains(uid);
  }

  bool _isVisibleToUser(Map<String, dynamic> data, String uid) =>
      !_isDeletedForEveryone(data) && !_isDeletedForUser(data, uid);

  String _previewTextForMessage(Map<String, dynamic> data) {
    // Encrypted messages — never read content here. The server never had
    // it. Return the opaque label so the inbox tile / FCM payload stays
    // consistent with what was originally written.
    if (data['enc'] is Map) return encryptedPreviewLabel;
    final text = (data['text'] as String? ?? '').trim();
    if (text.isNotEmpty) return text;
    if ((data['stickerUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a sticker';
    }
    if ((data['sharedPostId'] as String?)?.trim().isNotEmpty == true) {
      return 'Shared a post';
    }
    if ((data['voiceUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Voice message';
    }
    if ((data['videoUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a video';
    }
    if ((data['fileUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a file';
    }
    if ((data['imageUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a photo';
    }
    if (data['location'] is Map) {
      return '📍 Shared a location';
    }
    return '';
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
      _latestVisibleMessageDoc({
    required String chatId,
    required String uid,
  }) async {
    final recent = await _messagesCol(chatId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    for (final doc in recent.docs) {
      if (_isVisibleToUser(doc.data(), uid)) return doc;
    }
    return null;
  }

  Future<ChatConversation> _hydrateConversationForViewer({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required String uid,
  }) async {
    final conv = ChatConversation.fromDoc(doc, uid);
    final latestVisible = await _latestVisibleMessageDoc(
      chatId: doc.id,
      uid: uid,
    );
    final unread = await _deriveUnreadFromMessages(chatId: doc.id, uid: uid);

    if (latestVisible == null) {
      return conv.copyWith(lastMessage: '', unreadCount: 0);
    }

    final data = latestVisible.data();
    return conv.copyWith(
      lastMessage: await _viewerPreviewForMessage(
        chatId: doc.id,
        meUid: uid,
        data: data,
      ),
      lastTime: (data['createdAt'] as Timestamp?)?.toDate() ?? conv.lastTime,
      unreadCount: unread,
    );
  }

  /// Inbox preview text from the viewer's perspective. For encrypted
  /// messages we attempt to decrypt locally — the server still only stores
  /// the opaque "🔒 Encrypted message" label, but on the device that holds
  /// the chat key we render the real text.
  Future<String> _viewerPreviewForMessage({
    required String chatId,
    required String meUid,
    required Map<String, dynamic> data,
  }) async {
    final env = data['enc'];
    if (env is Map) {
      try {
        final clear = await _e2ee.decryptForChat(
          chatId: chatId,
          meUid: meUid,
          envelope: Map<String, dynamic>.from(env),
        );
        if (clear != null && clear.isNotEmpty) {
          final payload = jsonDecode(clear);
          if (payload is Map) {
            // Mirrors the field map written in sendMessage: 't' is the
            // text body, 'rt' is reply-to text, etc.
            final text = (payload['t'] as String?)?.trim();
            if (text != null && text.isNotEmpty) return text;
          }
        }
      } catch (_) {
        // Fall through to the structural preview below.
      }
      // We have an envelope but couldn't decrypt it on this device — show
      // the placeholder rather than empty.
      return _previewFromMediaFields(data) ?? encryptedPreviewLabel;
    }
    return _previewTextForMessage(data);
  }

  /// Returns a structural preview ("Sent a photo", etc.) if the message
  /// has any media fields, otherwise null. Used as a fallback when an
  /// encrypted envelope can't be decrypted but the message has a media
  /// attachment whose presence is already visible to the server anyway.
  String? _previewFromMediaFields(Map<String, dynamic> data) {
    if ((data['stickerUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a sticker';
    }
    if ((data['sharedPostId'] as String?)?.trim().isNotEmpty == true) {
      return 'Shared a post';
    }
    if ((data['voiceUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Voice message';
    }
    if ((data['videoUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a video';
    }
    if ((data['fileUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a file';
    }
    if ((data['imageUrl'] as String?)?.trim().isNotEmpty == true) {
      return 'Sent a photo';
    }
    if (data['location'] is Map) return '📍 Shared a location';
    return null;
  }

  Future<void> _refreshChatSummary(String chatId) async {
    final chatSnap = await _chatDoc(chatId).get();
    if (!chatSnap.exists) return;

    final participants = List<String>.from(
      chatSnap.data()?['participants'] as List? ?? const [],
    );
    final ownerForSummary = participants.isNotEmpty ? participants.first : '';
    final latestVisible = ownerForSummary.isEmpty
        ? null
        : await _latestVisibleMessageDoc(
            chatId: chatId,
            uid: ownerForSummary,
          );

    if (latestVisible == null) {
      await _chatDoc(chatId).set({
        'lastMessage': '',
        'lastMessageSenderUid': '',
      }, SetOptions(merge: true));
      return;
    }

    final data = latestVisible.data();
    await _chatDoc(chatId).set({
      'lastMessage': _previewTextForMessage(data),
      'lastMessageSenderUid': (data['senderUid'] as String?) ?? '',
      'lastTime': data['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deterministic chat ID from two user IDs.
  String buildChatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Creates or retrieves the chat document between two users. Returns the
  /// chatId.
  ///
  /// [secret] (default `false`) opts the new chat into the legacy E2EE
  /// path: messages are encrypted client-side, the server only stores
  /// ciphertext, and history will not be recoverable on a reinstall
  /// without the user's recovery key. Normal chats store message text
  /// in plaintext on Firestore, so reinstall sees full history.
  ///
  /// Has no effect when the chat already exists — pre-existing chats keep
  /// whatever `secret` value they were created with. See [_isSecretChat]
  /// for how existing chats without an explicit flag are classified.
  Future<String> openChat({
    required String currentUid,
    required String otherUid,
    bool secret = false,
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
        'secret': secret,
      });
    }
    return id;
  }

  /// Returns true when [chatData] should be treated as end-to-end
  /// encrypted. Used by [sendMessage] and [streamMessages] to decide
  /// whether to invoke [_e2ee] at all.
  ///
  /// Rules:
  ///   * Explicit `secret: true` on the chat doc wins (new hybrid path).
  ///   * Explicit `secret: false` opts out of E2EE entirely.
  ///   * Missing `secret` field but legacy `e2ee: true` (written by
  ///     [_forceRotate] the first time the chat ever encrypted) — treat
  ///     as secret to preserve readability of old ciphertext on devices
  ///     that hold the key.
  ///   * Otherwise — normal/plaintext chat.
  ///
  /// This conservative default means existing chats from before the
  /// hybrid migration keep encrypting; users must opt-in to the new
  /// plaintext default when starting a brand-new chat.
  static bool _isSecretChat(Map<String, dynamic> chatData) {
    final flag = chatData['secret'];
    if (flag is bool) return flag;
    return chatData['e2ee'] == true;
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
    String? stickerUrl,
    String? stickerPackId,
    double? locationLat,
    double? locationLng,
    String? locationLabel,
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
    final normalizedStickerUrl = stickerUrl?.trim();
    final normalizedStickerPackId = stickerPackId?.trim();
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
    final hasSticker =
        normalizedStickerUrl != null && normalizedStickerUrl.isNotEmpty;
    final hasLocation = locationLat != null && locationLng != null;
    final normalizedLocationLabel = locationLabel?.trim();
    if (trimmedText.isEmpty &&
        !hasImage &&
        !hasVideo &&
        !hasFile &&
        !hasSharedPost &&
        !hasVoice &&
        !hasStoryRef &&
        !hasSticker &&
        !hasLocation) {
      return;
    }

    // Determine recipients for unread bookkeeping. For 1:1 we use the
    // receiverUid passed in. For groups we read participants from the
    // chat doc so every other member's unread count bumps.
    final chatSnap = await _chatDoc(chatId).get();
    final chatData = chatSnap.data() ?? {};
    final isGroup = (chatData['kind'] as String?) == 'group';
    final allParticipants =
        ((chatData['participants'] as List?)?.cast<String>() ?? const [])
            .toList();
    final recipients = isGroup
        ? allParticipants.where((u) => u != senderUid).toList()
        : <String>[
            if (receiverUid.trim().isNotEmpty)
              receiverUid.trim()
            else
              allParticipants.firstWhere(
                (u) => u != senderUid,
                orElse: () => '',
              ),
          ];

    // ── Hybrid E2EE gate ────────────────────────────────────────────────
    // Only secret chats (explicit `secret: true`, or legacy chats that
    // already have `e2ee: true` from a prior encryption rotation) go
    // through the AES-GCM wrap. Normal chats store message text in the
    // doc's plaintext fields so reinstalled users can read full history
    // from the server without holding any key.
    //
    // For secret chats: pack the small text-bearing fields into a single
    // JSON blob, encrypt with the per-chat session key, and store under
    // `enc`. Media URLs and structural fields (createdAt, senderUid, etc.)
    // stay in plaintext — they are required for sorting / rules / link
    // previews. The lock banner in ChatScreen explains what is and isn't
    // covered.
    //
    // For groups: the participant list is read from the chat doc so every
    // member gets a wrapped copy of the chat key. If membership has changed
    // since the last key was issued, _ensureChatKey rotates automatically
    // and archives the old wrapping so old messages stay readable for
    // members who were present then.
    Map<String, dynamic>? envelope;
    final isSecret = _isSecretChat(chatData);
    if (isSecret) {
      final participantsForKey = isGroup
          ? allParticipants.where((u) => u.isNotEmpty).toSet().toList()
          : <String>{senderUid, ...recipients}
              .where((u) => u.isNotEmpty)
              .toList();
      final payload = <String, dynamic>{
        if (trimmedText.isNotEmpty) 't': trimmedText,
        if (replyToText != null && replyToText.isNotEmpty) 'rt': replyToText,
        if (normalizedVoiceTranscript != null &&
            normalizedVoiceTranscript.isNotEmpty)
          'vt': normalizedVoiceTranscript,
        if (normalizedLocationLabel != null &&
            normalizedLocationLabel.isNotEmpty)
          'll': normalizedLocationLabel,
        if (normalizedFileName != null && normalizedFileName.isNotEmpty)
          'fn': normalizedFileName,
      };
      if (payload.isNotEmpty && participantsForKey.isNotEmpty) {
        try {
          envelope = await _e2ee.encryptForChat(
            chatId: chatId,
            senderUid: senderUid,
            participantUids: participantsForKey,
            plaintext: jsonEncode(payload),
          );
        } on E2EEUnavailable catch (e) {
          debugPrint('[e2ee] unavailable, falling back to plaintext: $e');
          envelope = null;
        } catch (e, st) {
          // Catch-all: never let an encryption failure block sending. The
          // user would otherwise be stuck unable to message at all if the
          // platform crypto plugin or Keystore is misbehaving on their
          // device.
          debugPrint(
              '[e2ee] encrypt FAILED, falling back to plaintext: $e\n$st');
          envelope = null;
        }
      }
    }

    final batch = _db.batch();
    final msgRef = _messagesCol(chatId).doc();
    final chatRef = _chatDoc(chatId);
    // For E2EE chats the server must never see message content. Replace the
    // preview with a generic encrypted-message label so the inbox tile,
    // FCM notification body (if backend reads `lastMessage`), and any other
    // server-side consumer all see the same opaque text.
    final lastMessage = (envelope != null)
        ? encryptedPreviewLabel
        : trimmedText.isNotEmpty
            ? trimmedText
            : hasSticker
                ? 'Sent a sticker'
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
                                    : hasLocation
                                        ? '📍 Shared a location'
                                        : '';

    final encrypted = envelope != null;
    batch.set(msgRef, {
      'senderUid': senderUid,
      if (!isGroup) 'receiverUid': receiverUid,
      // When encrypted, text-bearing fields are packed inside `enc`. Writing
      // an empty string for `text` keeps older readers (those that index by
      // `text`) from crashing on a missing field.
      'text': encrypted ? '' : trimmedText,
      if (encrypted) 'enc': envelope,
      'imageUrl': normalizedImageUrl,
      if (hasVideo) 'videoUrl': normalizedVideoUrl,
      if (hasFile) 'fileUrl': normalizedFileUrl,
      if (!encrypted &&
          hasFile &&
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
      if (!encrypted &&
          hasVoice &&
          normalizedVoiceTranscript != null &&
          normalizedVoiceTranscript.isNotEmpty)
        'voiceTranscript': normalizedVoiceTranscript,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      if (!encrypted && replyToText != null && replyToText.isNotEmpty)
        'replyToText': replyToText,
      if (replyToSenderUid != null && replyToSenderUid.isNotEmpty)
        'replyToSenderUid': replyToSenderUid,
      if (hasStoryRef) 'storyId': normalizedStoryId,
      if (hasStoryRef &&
          normalizedStoryImageUrl != null &&
          normalizedStoryImageUrl.isNotEmpty)
        'storyImageUrl': normalizedStoryImageUrl,
      if (hasSticker) 'stickerUrl': normalizedStickerUrl,
      if (hasSticker &&
          normalizedStickerPackId != null &&
          normalizedStickerPackId.isNotEmpty)
        'stickerPackId': normalizedStickerPackId,
      if (hasLocation) 'location': {'lat': locationLat, 'lng': locationLng},
      if (!encrypted &&
          hasLocation &&
          normalizedLocationLabel != null &&
          normalizedLocationLabel.isNotEmpty)
        'locationLabel': normalizedLocationLabel,
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

    try {
      await batch.commit();
    } catch (e, st) {
      debugPrint('[chat-send] commit FAILED: $e\n$st');
      rethrow;
    }
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
    await _chatDoc(chatId).update({
      'unread.$uid': 0,
      'lastSeenAt.$uid': FieldValue.serverTimestamp(),
    });

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
  ///
  /// To make opening a chat feel instant even when the conversation has
  /// hundreds of messages, the stream first yields a locally cached
  /// snapshot of the last [MessageCache.maxEntries] messages — no
  /// Firestore round trip, no AES-GCM decrypt. The live Firestore
  /// snapshot then takes over, and per-message decryption reuses the
  /// payload cache so any message we've already opened on this device
  /// doesn't get decrypted twice.
  ///
  /// If a message has an `enc` envelope but this device can't decrypt it
  /// (no key, wrong key, etc.) the message is yielded with
  /// [ChatMessage.encryptedUnreadable] set so the UI can show a padlock
  /// placeholder instead of an empty bubble.
  Stream<List<ChatMessage>> streamMessages(String chatId,
      {required String uid}) {
    // Fire-and-forget: patch any wrappedKeys entries that are missing for
    // current participants. This lets messages become readable when a
    // participant was absent when the key was first created. The patch is
    // idempotent — if everything is already wrapped it's a no-op. The
    // stream will re-emit on the Firestore update, making previously
    // locked messages decrypt successfully.
    unawaited(_patchWrappingsForChat(chatId: chatId, uid: uid));

    final controller = StreamController<List<ChatMessage>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    final cache = MessageCache.instance;
    // Mutated as we decrypt; persisted after each successful emission.
    final payloads = <String, String>{};
    // Tail of the in-flight cache write. Firestore's snapshot listener
    // fires events back-to-back, so without a chain two writes can
    // interleave and leave a half-written payload map paired with a
    // snapshot from a later event. Chaining keeps writes serialized
    // without blocking the UI emission.
    Future<void> writeChain = Future<void>.value();

    Future<void> emitCached() async {
      try {
        final snap = await cache.loadSnapshot(chatId);
        if (snap != null && snap.isNotEmpty && !controller.isClosed) {
          controller.add(snap.map(ChatMessage.fromCacheJson).toList());
        }
        payloads.addAll(await cache.loadPayloads(chatId));
      } catch (e) {
        debugPrint('[chat-cache] warmup failed for $chatId: $e');
      }
    }

    Future<void> onSnapshot(QuerySnapshot<Map<String, dynamic>> s) async {
      try {
        final visible =
            s.docs.where((doc) => _isVisibleToUser(doc.data(), uid)).toList();
        final out = <ChatMessage>[];
        for (final doc in visible) {
          out.add(await _decryptDoc(
            chatId: chatId,
            uid: uid,
            doc: doc,
            payloadCache: payloads,
          ));
        }
        if (controller.isClosed) return;
        controller.add(out);

        // Persist most-recent payloads + snapshot for the next open. We
        // only keep the tail of [visible] so the cache doesn't grow
        // unbounded on long chats. Writes are chained behind the previous
        // write so back-to-back Firestore events can't interleave.
        final tail = out.length <= MessageCache.maxEntries
            ? out
            : out.sublist(out.length - MessageCache.maxEntries);
        final tailIds = tail.map((m) => m.id).toSet();
        final trimmedPayloads = <String, String>{
          for (final entry in payloads.entries)
            if (tailIds.contains(entry.key)) entry.key: entry.value,
        };
        final snapshotJson = tail.map((m) => m.toCacheJson()).toList();
        writeChain = writeChain.then((_) async {
          await cache.savePayloads(chatId, trimmedPayloads);
          await cache.saveSnapshot(chatId, snapshotJson);
        }).catchError((Object e) {
          debugPrint('[chat-cache] persist failed for $chatId: $e');
        });
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller.onListen = () {
      emitCached().whenComplete(() {
        if (controller.isClosed) return;
        sub = _messagesCol(chatId)
            .orderBy('createdAt')
            .snapshots()
            .listen(onSnapshot, onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        });
      });
    };
    controller.onCancel = () async {
      await sub?.cancel();
      // Let the last cache write drain so we don't leave a partial file.
      await writeChain.catchError((Object _) {});
    };

    return controller.stream;
  }

  Future<void> _patchWrappingsForChat({
    required String chatId,
    required String uid,
  }) async {
    try {
      final chatSnap = await _chatDoc(chatId).get();
      final data = chatSnap.data() ?? {};
      // Non-secret chats never wrap keys, so there's nothing to patch.
      // Skip the work to avoid spurious Firestore writes (and to keep
      // normal chats clean of E2EE-side artifacts).
      if (!_isSecretChat(data)) return;
      final participants =
          ((data['participants'] as List?)?.cast<String>() ?? const [])
              .where((u) => u.isNotEmpty)
              .toList();
      if (participants.length < 2) return;
      await _e2ee.patchMissingWrappings(
        chatId: chatId,
        meUid: uid,
        participantUids: participants,
      );
    } catch (e) {
      debugPrint('[chat-patch] key patch failed for $chatId: $e');
    }
  }

  Future<ChatMessage> _decryptDoc({
    required String chatId,
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, String>? payloadCache,
  }) async {
    final data = doc.data();
    final env = data['enc'];
    if (env is! Map) return ChatMessage.fromDoc(doc);

    // Cache hit: skip the AES-GCM decrypt entirely. The envelope bytes
    // are immutable for a given msgId, so a hit is always valid.
    final cached = payloadCache?[doc.id];
    if (cached != null) {
      try {
        final payload = jsonDecode(cached);
        return ChatMessage.fromDoc(
          doc,
          decrypted: payload is Map ? Map<String, dynamic>.from(payload) : null,
        );
      } catch (_) {
        payloadCache?.remove(doc.id);
      }
    }

    try {
      final clear = await _e2ee.decryptForChat(
        chatId: chatId,
        meUid: uid,
        envelope: Map<String, dynamic>.from(env),
      );
      if (clear == null) {
        return ChatMessage.fromDoc(doc, decryptionFailed: true);
      }
      if (payloadCache != null) payloadCache[doc.id] = clear;
      final payload = jsonDecode(clear);
      return ChatMessage.fromDoc(
        doc,
        decrypted: payload is Map ? Map<String, dynamic>.from(payload) : null,
      );
    } catch (_) {
      return ChatMessage.fromDoc(doc, decryptionFailed: true);
    }
  }

  /// Real-time stream of all conversations for [uid], sorted by latest message.
  Stream<List<ChatConversation>> streamInbox(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .asyncMap((s) async {
      final withUnread = await Future.wait(
        s.docs.map((doc) => _hydrateConversationForViewer(doc: doc, uid: uid)),
      );

      // Hide chats that have no messages yet. openChat creates the doc
      // as soon as you visit a profile and tap "Message"; without this
      // filter the recipient saw a request notification for a chat the
      // other user never actually wrote to. Group chats stay visible
      // even when empty since the explicit invite already implies
      // intent. We use lastMessage as the gate (not lastTime) because
      // openChat sets a serverTimestamp on creation.
      final convs = withUnread
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

  Future<int> _deriveUnreadFromMessages({
    required String chatId,
    required String uid,
  }) async {
    try {
      final recent = await _messagesCol(chatId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      var count = 0;
      for (final doc in recent.docs) {
        final data = doc.data();
        if (!_isVisibleToUser(data, uid)) continue;
        if (data['senderUid'] == uid) continue;
        final seenBy = List<String>.from(data['seenBy'] as List? ?? const []);
        if (!seenBy.contains(uid)) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
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
    bool secret = false,
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
      'secret': secret,
    });
    return ref.id;
  }

  /// Admin-only: add a new member to an existing group.
  ///
  /// The chat key is NOT rotated here. By design, the newly-added member
  /// CANNOT read pre-existing messages — their public key isn't in any
  /// historical `wrappedKeys` entry, and the message envelopes reference
  /// older `kv` versions whose archive entries don't include them either.
  /// They will be wrapped into the next session key automatically when any
  /// existing member sends a message (lazy rotation in `_ensureChatKey`).
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
  ///
  /// The chat key is NOT rotated here. The next time any remaining member
  /// sends a message, `_ensureChatKey` notices that the wrappable
  /// participant set no longer matches `wrappedKeys` and rotates
  /// automatically — meaning the removed/left member can't decrypt
  /// anything sent after that point. This is the same behavior as
  /// WhatsApp groups: between removal and the next send, a removed member
  /// could theoretically still receive plaintext if they had a live
  /// snapshot listener, but in practice the rule below already kicks them
  /// out of `participants` and Firestore rules prevent further reads.
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

  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    await _messagesCol(chatId).doc(messageId).set({
      'deletedForUids': FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessageForEveryone({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    final msgRef = _messagesCol(chatId).doc(messageId);
    final snap = await msgRef.get();
    if (!snap.exists) return;

    final data = snap.data() ?? const <String, dynamic>{};
    if ((data['senderUid'] as String?) != uid) {
      throw StateError('Only the sender can delete this message for everyone.');
    }

    await msgRef.set({
      'deletedForEveryone': true,
      'deletedByUid': uid,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _refreshChatSummary(chatId);
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
    // Remove the local plaintext cache so deleted chats don't leave
    // decrypted message bodies on disk.
    unawaited(MessageCache.instance.clear(chatId));
  }

  /// Mute / unmute [chatId] for the given [uid]. The backend FCM dispatcher
  /// is expected to skip push delivery when the recipient appears in
  /// `mutedFor`. The chat tile still appears in the inbox; only push
  /// notifications are suppressed.
  Future<void> setMuted({
    required String chatId,
    required String uid,
    required bool muted,
  }) async {
    await _chatDoc(chatId).set({
      'mutedFor':
          muted ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    }, SetOptions(merge: true));
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
