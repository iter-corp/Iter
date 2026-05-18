import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chat_service.dart';
import '../services/e2ee/e2ee_service.dart';
import '../services/e2ee/key_manager.dart';
import '../services/presence_service.dart';
import '../services/typing_service.dart';
import 'auth_providers.dart';

final keyManagerProvider = Provider<KeyManager>((_) => KeyManager());

/// Current state of the local E2EE keypair vs. what Firestore advertises
/// for the signed-in user. Surfaces the multi-device collision case so
/// chat UIs can show a "another device replaced your encryption key"
/// banner. Re-emits when invalidated (call `ref.invalidate` after a
/// republish / recovery flow). Default value [KeySyncState.unknown] until
/// the first check completes.
final keySyncStateProvider =
    StateProvider<KeySyncState>((_) => KeySyncState.unknown);

/// Runs [KeyManager.checkKeyPairSync] for the current user and writes
/// the result into [keySyncStateProvider]. Auto-runs on auth change from
/// main.dart; can be invalidated to force a recheck after a recovery
/// flow republishes the keypair.
final keySyncCheckProvider =
    FutureProvider.family<KeySyncState, String>((ref, uid) async {
  final result = await ref.read(keyManagerProvider).checkKeyPairSync(uid);
  ref.read(keySyncStateProvider.notifier).state = result;
  return result;
});

/// Compares the live published pub-key of [peerUid] against the
/// fingerprint we last observed for that peer (per-`(meUid, peerUid)`
/// pair, persisted in secure storage). Drives the "security code
/// changed" banner in 1:1 secret chats. Family key is
/// `"meUid|peerUid"`. Auto-disposes; can be invalidated after the
/// user acknowledges a change to refresh the cached state.
final peerKeyStateProvider =
    FutureProvider.autoDispose.family<PeerKeyState, String>((ref, key) async {
  final sep = key.indexOf('|');
  if (sep < 0) return PeerKeyState.unknown;
  final meUid = key.substring(0, sep);
  final peerUid = key.substring(sep + 1);
  return ref.read(keyManagerProvider).checkPeerKey(
        meUid: meUid,
        peerUid: peerUid,
      );
});

/// For a secret group chat, returns the subset of [participantUids]
/// that do NOT have a published public key — i.e. members who will
/// silently miss any encrypted message you send. The chat-screen UI
/// renders this as a "won't be readable for X" warning above the
/// composer. Family key is the comma-joined sorted participant list
/// so callers don't have to memoize themselves.
final missingPubKeyMembersProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, key) async {
  if (key.isEmpty) return const [];
  final uids = key.split(',').where((s) => s.isNotEmpty).toList();
  final km = ref.read(keyManagerProvider);
  final missing = <String>[];
  for (final uid in uids) {
    final pub = await km.fetchPublicKey(uid);
    if (pub == null) missing.add(uid);
  }
  return missing;
});

/// Whether to show the "set a real recovery password" prompt on top of
/// the inbox. True when the signed-in user is still using the legacy
/// uid-derived recovery password and hasn't dismissed the banner this
/// session. Flipped via [legacyRecoveryPromptDismissedProvider].
final shouldPromptLegacyRecoveryProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  if (ref.watch(legacyRecoveryPromptDismissedProvider)) return false;
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return false;
  final chosen =
      await ref.read(keyManagerProvider).hasUserChosenRecoveryPassword(uid);
  return !chosen;
});

/// Per-session dismissal flag for the legacy-recovery prompt. Resets on
/// app restart so users who keep deferring still see it on the next
/// launch, but they aren't nagged repeatedly during the same session.
final legacyRecoveryPromptDismissedProvider =
    StateProvider<bool>((_) => false);

final e2eeServiceProvider = Provider<E2EEService>((ref) {
  return E2EEService(keyManager: ref.watch(keyManagerProvider));
});

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(e2ee: ref.watch(e2eeServiceProvider)),
);
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
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, chatId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatServiceProvider).streamMessages(chatId, uid: uid);
});

/// Raw chat doc stream — used by the chat screen to detect group vs
/// direct, and to render the correct header.
final chatDocProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, chatId) {
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
