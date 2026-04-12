import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/model/post_model.dart';
import '../services/post_service.dart';

final postServiceProvider = Provider<PostService>((_) => PostService());

final feedProvider = StreamProvider<List<Post>>(
  (ref) => ref.watch(postServiceProvider).streamFeed(),
);

final userPostsProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(postServiceProvider).streamUserPosts(uid),
);

final isLikedProvider = StreamProvider.family<bool, String>(
  (ref, postId) => ref.watch(postServiceProvider).streamIsLiked(postId),
);
