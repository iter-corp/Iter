import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/poll_service.dart';

final pollServiceProvider = Provider<PollService>((_) => PollService());

/// Polls for a parentPath (e.g. "chats/{id}" or "eventChats/{id}").
final pollsProvider =
    StreamProvider.family.autoDispose<List<Poll>, String>((ref, parentPath) {
  return ref.watch(pollServiceProvider).streamPolls(parentPath);
});

/// Key: "{parentPath}::{pollId}"
final pollVotesProvider =
    StreamProvider.family.autoDispose<List<PollVote>, String>((ref, key) {
  final i = key.indexOf('::');
  return ref.watch(pollServiceProvider).streamVotes(
        key.substring(0, i),
        key.substring(i + 2),
      );
});

final myVoteProvider =
    StreamProvider.family.autoDispose<PollVote?, String>((ref, key) {
  final i = key.indexOf('::');
  return ref.watch(pollServiceProvider).streamMyVote(
        key.substring(0, i),
        key.substring(i + 2),
      );
});
