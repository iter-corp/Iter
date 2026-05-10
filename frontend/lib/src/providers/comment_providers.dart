import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/comment_service.dart';
import 'auth_providers.dart';

final commentServiceProvider =
    Provider<CommentService>((_) => CommentService());

/// Wraps [factory] with up to 3 retries (with back-off) so that a transient
/// permission-denied caused by the auth token not being ready yet doesn't
/// surface as a permanent error.
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

final commentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  // Wait for the auth token to be ready before opening the Firestore stream,
  // then wrap with retry to handle the transient permission-denied that can
  // occur right after login while the Firestore SDK processes the new token.
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final service = ref.watch(commentServiceProvider);
  return _retryStream(() => service.streamComments(postId));
});

typedef UserAnswerReactionArgs = ({
  String postId,
  String commentId,
  String uid,
});

final userAnswerReactionProvider =
    StreamProvider.family<String?, UserAnswerReactionArgs>((ref, args) {
  // Gate on the auth provider that eagerly fetches the current token, then
  // retry because Firestore can still lag one auth tick behind FirebaseAuth.
  final user = ref.watch(authStateProvider).value;
  if (user == null || user.uid != args.uid) return const Stream.empty();
  final service = ref.watch(commentServiceProvider);
  return _retryStream(
    () => service.streamUserAnswerReaction(
      postId: args.postId,
      commentId: args.commentId,
      uid: args.uid,
    ),
  );
});
