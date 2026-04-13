import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/comment_service.dart';

final commentServiceProvider =
    Provider<CommentService>((_) => CommentService());

final commentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  return ref.watch(commentServiceProvider).streamComments(postId);
});
