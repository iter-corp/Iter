import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/reaction_service.dart';

final reactionServiceProvider = Provider<ReactionService>((_) => ReactionService());

/// Key format: "parentPath::messageId"
/// Streams the current user's emoji reaction for a specific message.
final myReactionProvider = StreamProvider.family<String?, String>((ref, key) {
  final parts = key.split('::');
  if (parts.length != 2) return Stream.value(null);
  return ref.watch(reactionServiceProvider).streamMyReaction(
        parentPath: parts[0],
        messageId: parts[1],
      );
});

/// Key format: "parentPath::messageId"
/// Streams aggregated emoji → count map for a specific message.
final reactionCountsProvider =
    StreamProvider.family<Map<String, int>, String>((ref, key) {
  final parts = key.split('::');
  if (parts.length != 2) return Stream.value({});
  return ref.watch(reactionServiceProvider).streamReactionCounts(
        parentPath: parts[0],
        messageId: parts[1],
      );
});
