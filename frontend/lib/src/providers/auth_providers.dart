import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/user_service.dart';

final authServiceProvider = Provider<AuthService>((_) => AuthService());
final userServiceProvider = Provider<UserService>((_) => UserService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges.asyncMap((user) async {
    if (user != null) {
      try {
        // Confirm the token is in the Firebase Auth cache.
        await user.getIdToken();
        // Force the Firestore SDK to reconnect with the new credentials.
        // disableNetwork() was called during sign-out; this re-enables it so
        // all subsequent stream subscriptions open with a valid auth token.
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {
        // Non-fatal — Firestore will retry on its own.
      }
    }
    return user;
  });
});

final currentUserDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(userServiceProvider).streamUser(user.uid);
});

/// Live user doc for any uid. Used to render an author's current avatar and
/// username on content that was written in the past (comments, posts, etc.)
/// so updated profile info is reflected retroactively.
final userByUidProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value(null);
  return ref.watch(userServiceProvider).streamUser(uid);
});
