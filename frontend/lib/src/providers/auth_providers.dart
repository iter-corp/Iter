import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/user_service.dart';

/// Retries [factory] up to 3 times on error with increasing delays.
/// Used to guard against the transient permission-denied that can occur
/// when the Firestore SDK hasn't yet received the new auth token by the
/// time the first snapshot fires.
Stream<T> _retryStream<T>(Stream<T> Function() factory) {
  StreamSubscription<T>? innerSub;
  late StreamController<T> controller;
  bool disposed = false;

  void attempt(int n) {
    if (disposed) return;
    innerSub = factory().listen(
      controller.add,
      onDone: controller.close,
      onError: (e, st) {
        if (disposed) return;
        if (n < 3) {
          Future.delayed(Duration(milliseconds: 600 * (n + 1)), () {
            if (!disposed && !controller.isClosed) attempt(n + 1);
          });
        } else {
          if (!controller.isClosed) {
            controller.addError(e, st as StackTrace);
            controller.close();
          }
        }
      },
      cancelOnError: true,
    );
  }

  controller = StreamController<T>(
    onListen: () => attempt(0),
    onCancel: () {
      disposed = true;
      innerSub?.cancel();
    },
  );

  return controller.stream;
}

final authServiceProvider = Provider<AuthService>((_) => AuthService());
final userServiceProvider = Provider<UserService>((_) => UserService());

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges.asyncMap((user) async {
    if (user != null) {
      try {
        // Force the SDK to cache a valid token before any Firestore stream
        // opens. Without this, currentUserDocProvider can start a snapshot
        // listener in the narrow window between signInWithCredential completing
        // and the Firestore client receiving the new auth token, which produces
        // a transient permission-denied on the very first snapshot.
        await user.getIdToken();
        // Yield to the event loop so the Firestore SDK's own auth-state
        // listener (which runs on a separate async channel) gets a chance
        // to process the new token before downstream providers open any
        // Firestore streams.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } catch (_) {
        // Non-fatal — the Firestore SDK will retry with a fresh token.
      }
    }
    return user;
  });
});

final currentUserDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  // Select only the UID so this provider only rebuilds when the signed-in
  // user actually changes. Firebase Auth can re-emit the same user multiple
  // times (e.g. token refresh), which would otherwise restart the Firestore
  // stream and produce a spurious AsyncLoading state that causes the router
  // to flash back to /splash and then re-navigate to the current route.
  final uid = ref.watch(authStateProvider.select((v) => v.value?.uid));
  if (uid == null) return Stream.value(null);
  final userService = ref.watch(userServiceProvider);
  return _retryStream(() => userService.streamUser(uid));
});

/// Live user doc for any uid. Used to render an author's current avatar and
/// username on content that was written in the past (comments, posts, etc.)
/// so updated profile info is reflected retroactively.
final userByUidProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value(null);
  return ref.watch(userServiceProvider).streamUser(uid);
});
