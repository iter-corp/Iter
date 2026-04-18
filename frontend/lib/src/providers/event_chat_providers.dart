import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/event_chat_service.dart';
import 'auth_providers.dart';

final eventChatServiceProvider =
    Provider<EventChatService>((_) => EventChatService());

/// Stream of every event chat the current user is a member of.
final myEventChatsProvider =
    StreamProvider.autoDispose<List<EventChatSummary>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(eventChatServiceProvider).streamMyEventChats(uid);
});

/// Messages stream for a specific event chat.
final eventChatMessagesProvider =
    StreamProvider.family<List<EventChatMessage>, String>((ref, eventId) {
  return ref.watch(eventChatServiceProvider).streamMessages(eventId);
});

/// Admin uid for the event chat (determines whether compose is shown).
final eventChatAdminProvider =
    StreamProvider.family<String?, String>((ref, eventId) {
  return ref.watch(eventChatServiceProvider).streamAdminUid(eventId);
});

/// Live list of members of an event chat.
final eventChatMembersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) {
  return ref.watch(eventChatServiceProvider).streamMembers(eventId);
});

/// For each of two users, look up which event group chats they share
/// (either as admin or as a member). Returns the most recently-joined
/// shared event as a small summary: {eventId, eventTitle}.
///
/// Key format: "uidA|uidB"
final sharedEventProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, String>((ref, key) async {
  try {
    final parts = key.split('|');
    if (parts.length != 2 || parts[0] == parts[1]) return null;
    final uidA = parts[0];
    final uidB = parts[1];
    final svc = ref.watch(eventChatServiceProvider);

    final aChats = await svc.streamMyEventChats(uidA).first;
    final bChats = await svc.streamMyEventChats(uidB).first;
    if (aChats.isEmpty || bChats.isEmpty) return null;

    final bIds = {for (final c in bChats) c.eventId};
    final shared = aChats.where((c) => bIds.contains(c.eventId)).toList();
    if (shared.isEmpty) return null;

    shared.sort((x, y) {
      final xt = x.lastTime;
      final yt = y.lastTime;
      if (xt == null) return 1;
      if (yt == null) return -1;
      return yt.compareTo(xt);
    });
    return {
      'eventId': shared.first.eventId,
      'eventTitle': shared.first.eventTitle,
    };
  } catch (_) {
    // Silently return null on permission-denied or missing index errors.
    return null;
  }
});
