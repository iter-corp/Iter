import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/reaction_service.dart';

final reactionServiceProvider =
    Provider<ReactionService>((_) => ReactionService());

/// Key format: "{parentPath}::{messageId}"
final reactionCountsProvider =
    StreamProvider.family.autoDispose<Map<String, int>, String>((ref, key) {
  final i = key.indexOf('::');
  final parentPath = key.substring(0, i);
  final messageId = key.substring(i + 2);
  return ref.watch(reactionServiceProvider).streamCounts(
        parentPath: parentPath,
        messageId: messageId,
      );
});

final myReactionProvider =
    StreamProvider.family.autoDispose<String?, String>((ref, key) {
  final i = key.indexOf('::');
  final parentPath = key.substring(0, i);
  final messageId = key.substring(i + 2);
  return ref.watch(reactionServiceProvider).streamMine(
        parentPath: parentPath,
        messageId: messageId,
      );
});
