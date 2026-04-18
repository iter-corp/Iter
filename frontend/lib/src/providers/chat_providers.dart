import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chat_service.dart';
import '../services/presence_service.dart';
import '../services/typing_service.dart';
import 'auth_providers.dart';

final chatServiceProvider = Provider<ChatService>((_) => ChatService());
final presenceServiceProvider =
    Provider<PresenceService>((_) => PresenceService());
final typingServiceProvider = Provider<TypingService>((_) => TypingService());

/// All conversations for the current user, sorted by latest message.
final inboxProvider = StreamProvider<List<ChatConversation>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatServiceProvider).streamInbox(uid);
});

final requestsProvider = StreamProvider<List<ChatConversation>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatServiceProvider).streamRequests(uid);
});

final acceptedInboxProvider = StreamProvider<List<ChatConversation>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatServiceProvider).streamAcceptedInbox(uid);
});

/// Messages for a specific chat, oldest first.
final messagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, chatId) {
  return ref.watch(chatServiceProvider).streamMessages(chatId);
});

/// Raw chat doc stream — used by the chat screen to detect group vs
/// direct, and to render the correct header.
final chatDocProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, chatId) {
  return FirebaseFirestore.instance
      .collection('chats')
      .doc(chatId)
      .snapshots()
      .map((s) => s.data());
});

/// Whether [otherUid] is typing in [chatId].
/// Key format: "chatId|otherUid"
final typingWatchProvider = StreamProvider.family<bool, String>((ref, key) {
  final sep = key.indexOf('|');
  final chatId = key.substring(0, sep);
  final otherUid = key.substring(sep + 1);
  return ref.watch(typingServiceProvider).listenTyping(chatId, otherUid);
});

/// Presence (online/offline) for any user.
final presenceWatchProvider =
    StreamProvider.family<PresenceData, String>((ref, uid) {
  return ref.watch(presenceServiceProvider).listenPresence(uid);
});
