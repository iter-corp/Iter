import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/contact_request_service.dart';
import 'auth_providers.dart';

final contactRequestServiceProvider =
    Provider<ContactRequestService>((_) => ContactRequestService());

/// The signed-in user's own contact threads, newest first. Empty when
/// signed out.
final myContactRequestsProvider =
    StreamProvider<List<ContactRequest>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(contactRequestServiceProvider).streamMyRequests(uid);
});

/// Every contact thread across the app, newest activity first. Admin
/// dashboards only — Firestore rules will reject reads for non-admins
/// past their own uid.
final allContactRequestsProvider =
    StreamProvider<List<ContactRequest>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(contactRequestServiceProvider).streamAll();
});

/// Messages inside a specific contact thread.
final contactRequestMessagesProvider = StreamProvider.autoDispose
    .family<List<ContactRequestMessage>, String>((ref, requestId) {
  return ref
      .watch(contactRequestServiceProvider)
      .streamMessages(requestId);
});

/// True when there is at least one thread waiting for an admin reply.
/// Drives the unread dot on the admin dashboard tile.
final hasUnreadContactRequestsProvider = Provider<bool>((ref) {
  final list = ref.watch(allContactRequestsProvider).valueOrNull;
  if (list == null) return false;
  return list.any((r) => r.unreadByAdmin);
});

/// True when the signed-in user has an unanswered/unread admin reply
/// on any of their threads. Lets the user-side Settings tile show a
/// dot so they notice the response.
final hasUnreadAdminReplyProvider = Provider<bool>((ref) {
  final list = ref.watch(myContactRequestsProvider).valueOrNull;
  if (list == null) return false;
  return list.any((r) => r.unreadByUser);
});
