import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../utils/media_cache.dart';
import 'api_client.dart';
import 'realtime_client.dart';

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
  final String? sharedEventId;
  final String? voiceUrl;
  final int? voiceDurationMs;
  final String? stickerUrl;
  final String? stickerPackId;
  final String? voiceTranscript;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderUid;
  final String? storyId;
  final String? storyImageUrl;
  final double? locationLat;
  final double? locationLng;
  final String? locationLabel;
  final DateTime? createdAt;
  final List<String> seenBy;
  final bool profanityFiltered;
  final bool encryptedUnreadable;

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
    this.sharedEventId,
    this.voiceUrl,
    this.voiceDurationMs,
    this.stickerUrl,
    this.stickerPackId,
    this.voiceTranscript,
    this.replyToId,
    this.replyToText,
    this.replyToSenderUid,
    this.storyId,
    this.storyImageUrl,
    this.locationLat,
    this.locationLng,
    this.locationLabel,
    this.createdAt,
    this.seenBy = const [],
    this.profanityFiltered = false,
    this.encryptedUnreadable = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> d) {
    DateTime? createdAt;
    final rawCreated = d['createdAt'];
    if (rawCreated is String) createdAt = DateTime.tryParse(rawCreated);
    if (rawCreated is int) createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreated);

    return ChatMessage(
      id: (d['id'] as String?) ?? '',
      senderUid: (d['senderUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      imageUrl: d['imageUrl'] != null ? normalizeMediaUrl(d['imageUrl'] as String?) : null,
      videoUrl: d['videoUrl'] != null ? normalizeMediaUrl(d['videoUrl'] as String?) : null,
      fileUrl: d['fileUrl'] != null ? normalizeMediaUrl(d['fileUrl'] as String?) : null,
      fileName: d['fileName'] as String?,
      fileMimeType: d['fileMimeType'] as String?,
      fileSizeBytes: (d['fileSizeBytes'] as num?)?.toInt(),
      sharedPostId: d['sharedPostId'] as String?,
      sharedEventId: d['sharedEventId'] as String?,
      voiceUrl: d['voiceUrl'] != null ? normalizeMediaUrl(d['voiceUrl'] as String?) : null,
      voiceDurationMs: (d['voiceDurationMs'] as num?)?.toInt(),
      stickerUrl: d['stickerUrl'] != null ? normalizeMediaUrl(d['stickerUrl'] as String?) : null,
      stickerPackId: d['stickerPackId'] as String?,
      voiceTranscript: d['voiceTranscript'] as String?,
      replyToId: d['replyToId'] as String?,
      replyToText: d['replyToText'] as String?,
      replyToSenderUid: d['replyToSenderUid'] as String?,
      storyId: d['storyId'] as String?,
      storyImageUrl: d['storyImageUrl'] != null ? normalizeMediaUrl(d['storyImageUrl'] as String?) : null,
      locationLat: (d['locationLat'] as num?)?.toDouble(),
      locationLng: (d['locationLng'] as num?)?.toDouble(),
      locationLabel: d['locationLabel'] as String?,
      createdAt: createdAt,
      seenBy: List<String>.from(d['seenBy'] as List? ?? const []),
      profanityFiltered: d['profanityFiltered'] == true,
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
  final bool isRequest;
  final List<String> mutedFor;
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
    this.mutedFor = const [],
    this.isGroup = false,
    this.groupName = '',
    this.groupAvatarUrl = '',
    this.adminUid = '',
    this.participants = const [],
  });

  bool isMutedBy(String uid) => mutedFor.contains(uid);

  factory ChatConversation.fromJson(Map<String, dynamic> d) {
    DateTime? lastTime;
    final rawTime = d['lastTime'];
    if (rawTime is String) lastTime = DateTime.tryParse(rawTime);
    if (rawTime is int) lastTime = DateTime.fromMillisecondsSinceEpoch(rawTime);

    return ChatConversation(
      chatId: (d['chatId'] as String?) ?? '',
      otherUid: (d['otherUid'] as String?) ?? '',
      otherUsername: (d['otherUsername'] as String?) ?? 'User',
      otherAvatarUrl: normalizeMediaUrl((d['otherAvatarUrl'] as String?) ?? ''),
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastTime: lastTime,
      unreadCount: (d['unreadCount'] as num?)?.toInt() ?? 0,
      isRequest: d['isRequest'] == true,
      mutedFor: List<String>.from(d['mutedFor'] as List? ?? const []),
      isGroup: d['isGroup'] == true,
      groupName: (d['groupName'] as String?) ?? '',
      groupAvatarUrl: normalizeMediaUrl((d['groupAvatarUrl'] as String?) ?? ''),
      adminUid: (d['adminUid'] as String?) ?? '',
      participants: List<String>.from(d['participants'] as List? ?? const []),
    );
  }
}

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal() {
    // Whenever a new message arrives over WebSocket, refresh conversations
    // so the inbox updates unread counts and latest messages in real time!
    RealtimeClient.instance.messageStream.listen((_) {
      refreshConversations();
    });
  }

  final Map<String, StreamController<List<ChatMessage>>> _messagesControllers = {};
  final Map<String, List<ChatMessage>> _messagesCache = {};

  final BehaviorSubject<List<ChatConversation>> _convosSubject =
      BehaviorSubject<List<ChatConversation>>();
  final BehaviorSubject<List<ChatConversation>> _requestsSubject =
      BehaviorSubject<List<ChatConversation>>();

  Stream<List<ChatConversation>> streamConversations(String uid) {
    refreshConversations();
    return _convosSubject.stream;
  }

  Stream<List<ChatConversation>> streamInbox(String uid) =>
      streamConversations(uid);

  Stream<List<ChatConversation>> streamAcceptedInbox(String uid) =>
      streamConversations(uid);

  Stream<List<ChatConversation>> streamConversationRequests(String uid) {
    refreshRequests();
    return _requestsSubject.stream;
  }

  Stream<List<ChatConversation>> streamRequests(String uid) =>
      streamConversationRequests(uid);

  Future<void> refreshConversations() async {
    try {
      final res = await ApiClient.instance.get('/chats/conversations');
      if (res is List) {
        final list = res
            .whereType<Map<String, dynamic>>()
            .map(ChatConversation.fromJson)
            .toList();
        _convosSubject.add(list);
      } else {
        if (!_convosSubject.hasValue) {
          _convosSubject.add(const []);
        }
      }
    } catch (e) {
      debugPrint('[ChatService] refreshConversations error: $e');
      if (!_convosSubject.hasValue) {
        _convosSubject.add(const []);
      }
    }
  }

  Future<void> refreshRequests() async {
    try {
      final res = await ApiClient.instance.get('/chats/conversations', queryParams: {'type': 'requests'});
      if (res is List) {
        final list = res
            .whereType<Map<String, dynamic>>()
            .map(ChatConversation.fromJson)
            .toList();
        _requestsSubject.add(list);
      } else {
        if (!_requestsSubject.hasValue) {
          _requestsSubject.add(const []);
        }
      }
    } catch (e) {
      debugPrint('[ChatService] refreshRequests error: $e');
      if (!_requestsSubject.hasValue) {
        _requestsSubject.add(const []);
      }
    }
  }

  Stream<List<ChatMessage>> streamMessages(String chatId, {String? uid}) {
    if (!_messagesControllers.containsKey(chatId) || _messagesControllers[chatId]!.isClosed) {
      _messagesControllers[chatId] = StreamController<List<ChatMessage>>.broadcast();

      // Listen to realtime WebSocket message stream
      RealtimeClient.instance.messageStream.listen((data) {
        if (data['chatId'] == chatId) {
          final newMsg = ChatMessage.fromJson(data);
          final current = _messagesCache[chatId] ?? [];
          if (!current.any((m) => m.id == newMsg.id)) {
            current.add(newMsg);
            _messagesCache[chatId] = current;
            _messagesControllers[chatId]?.add(current);
          }
        }
      });
    }

    if (_messagesCache.containsKey(chatId)) {
      Timer.run(() => _messagesControllers[chatId]?.add(_messagesCache[chatId]!));
    }

    refreshMessages(chatId);
    return _messagesControllers[chatId]!.stream;
  }

  Future<void> refreshMessages(String chatId) async {
    try {
      final res = await ApiClient.instance.get('/chats/$chatId/messages');
      if (res is List) {
        final list = res
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList();
        _messagesCache[chatId] = list;
        _messagesControllers[chatId]?.add(list);
      }
    } catch (e) {
      debugPrint('[ChatService] refreshMessages error: $e');
    }
  }

  Future<String> sendMessage({
    required String chatId,
    required String text,
    String? senderUid,
    String? receiverUid,
    bool? senderOnly,
    String? imageUrl,
    String? videoUrl,
    String? fileUrl,
    String? fileName,
    String? fileMimeType,
    int? fileSizeBytes,
    String? voiceUrl,
    int? voiceDurationMs,
    String? voiceTranscript,
    String? stickerUrl,
    String? stickerPackId,
    String? sharedPostId,
    String? sharedEventId,
    String? storyId,
    String? storyImageUrl,
    String? replyToId,
    String? replyToText,
    String? replyToSenderUid,
    double? locationLat,
    double? locationLng,
    String? locationLabel,
  }) async {
    final payload = {
      'text': text,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileMimeType': fileMimeType,
      'fileSizeBytes': fileSizeBytes,
      'voiceUrl': voiceUrl,
      'voiceDurationMs': voiceDurationMs,
      'voiceTranscript': voiceTranscript,
      'stickerUrl': stickerUrl,
      'stickerPackId': stickerPackId,
      'sharedPostId': sharedPostId,
      'sharedEventId': sharedEventId,
      'storyId': storyId,
      'storyImageUrl': storyImageUrl,
      'replyToId': replyToId,
      'replyToText': replyToText,
      'replyToSenderUid': replyToSenderUid,
      'locationLat': locationLat,
      'locationLng': locationLng,
      'locationLabel': locationLabel,
    };

    final res = await ApiClient.instance.post('/chats/$chatId/messages', body: payload);
    final msgId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshMessages(chatId);
    refreshConversations();
    return msgId;
  }

  Future<void> markAsSeen(String chatId, String uid) async {
    await ApiClient.instance.post('/chats/$chatId/seen');
  }

  Future<void> markSeen({required String chatId, String? uid}) async {
    await markAsSeen(chatId, uid ?? '');
  }

  Future<void> toggleMute(String chatId, String uid) async {
    await ApiClient.instance.post('/chats/$chatId/mute');
    refreshConversations();
  }

  Future<void> setMuted({required String chatId, required String uid, required bool muted}) async {
    await toggleMute(chatId, uid);
  }

  Future<void> setAutoDeletePeriod({required String chatId, dynamic period}) async {}

  Future<void> deleteMessageForEveryone({required String chatId, required String messageId, String? uid}) async {
    try {
      await ApiClient.instance.delete('/chats/$chatId/messages/$messageId');
      refreshMessages(chatId);
    } catch (_) {}
  }

  Future<void> deleteMessageForMe({required String chatId, required String messageId, required String uid}) async {
    try {
      await ApiClient.instance.delete('/chats/$chatId/messages/$messageId');
      refreshMessages(chatId);
    } catch (_) {}
  }

  Future<String> getOrCreateDirectChat(String otherUid) async {
    final res = await ApiClient.instance.get('/chats/direct/$otherUid');
    if (res is Map<String, dynamic>) {
      return res['id'] as String? ?? '';
    }
    return '';
  }

  Future<String> openChat({String? currentUid, required String otherUid}) async {
    return getOrCreateDirectChat(otherUid);
  }

  Future<String> createGroupChat({
    required String name,
    String? avatarUrl,
    required List<String> memberUids,
  }) async {
    final payload = {
      'groupName': name,
      'groupAvatarUrl': avatarUrl,
      'memberUids': memberUids,
    };

    final res = await ApiClient.instance.post('/chats/group', body: payload);
    final chatId = (res is Map<String, dynamic>)
        ? (res['id'] as String? ?? '')
        : res.toString();

    refreshConversations();
    return chatId;
  }

  Future<String> createGroup({
    String? name,
    String? groupName,
    String? creatorUid,
    String? avatarUrl,
    required List<String> memberUids,
  }) =>
      createGroupChat(
        name: groupName ?? name ?? 'Group',
        avatarUrl: avatarUrl,
        memberUids: memberUids,
      );

  Future<void> leaveOrRemoveGroupMember({required String chatId, required String uid}) async {
    try {
      await ApiClient.instance.post('/chats/$chatId/leave');
      refreshConversations();
    } catch (_) {}
  }

  Future<void> deleteChat(String chatId) async {
    await ApiClient.instance.delete('/chats/$chatId');
    refreshConversations();
  }

  Future<void> deleteGroup(String chatId) async {
    await deleteChat(chatId);
  }
}
