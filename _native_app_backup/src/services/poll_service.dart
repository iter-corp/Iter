import 'dart:async';
import 'api_client.dart';

enum PollVisibility { public, secret }

PollVisibility _visFrom(String? s) =>
    s == 'secret' ? PollVisibility.secret : PollVisibility.public;

class Poll {
  final String id;
  final String question;
  final List<String> options;
  final String createdByUid;
  final DateTime? createdAt;
  final PollVisibility visibility;
  final bool closed;

  const Poll({
    required this.id,
    required this.question,
    required this.options,
    required this.createdByUid,
    required this.createdAt,
    required this.visibility,
    required this.closed,
  });

  factory Poll.fromJson(Map<String, dynamic> d) {
    DateTime? createdAt;
    final raw = d['createdAt'];
    if (raw is String) createdAt = DateTime.tryParse(raw);
    if (raw is int) createdAt = DateTime.fromMillisecondsSinceEpoch(raw);

    return Poll(
      id: (d['id'] as String?) ?? '',
      question: (d['question'] as String?) ?? '',
      options: ((d['options'] as List?) ?? const []).cast<String>(),
      createdByUid: (d['createdByUid'] as String?) ?? '',
      createdAt: createdAt,
      visibility: _visFrom(d['visibility'] as String?),
      closed: d['closed'] == true,
    );
  }
}

class PollVote {
  final String uid;
  final int optionIndex;
  final DateTime? createdAt;

  const PollVote({
    required this.uid,
    required this.optionIndex,
    this.createdAt,
  });

  factory PollVote.fromJson(Map<String, dynamic> d) {
    DateTime? createdAt;
    final raw = d['createdAt'];
    if (raw is String) createdAt = DateTime.tryParse(raw);
    if (raw is int) createdAt = DateTime.fromMillisecondsSinceEpoch(raw);

    return PollVote(
      uid: (d['uid'] as String?) ?? '',
      optionIndex: (d['optionIndex'] as num?)?.toInt() ?? -1,
      createdAt: createdAt,
    );
  }
}

class PollService {
  static final PollService _instance = PollService._internal();
  factory PollService() => _instance;
  PollService._internal();

  final Map<String, StreamController<List<Poll>>> _pollControllers = {};

  Future<String> createPoll({
    required String parentPath,
    required String question,
    required List<String> options,
    required PollVisibility visibility,
  }) async {
    final cleanOpts = options
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .take(10)
        .toList();

    final parts = parentPath.split('/');
    final targetType = parts.isNotEmpty ? parts[0] : 'chat';
    final targetId = parts.length > 1 ? parts[1] : '';

    final payload = {
      'question': question.trim(),
      'options': cleanOpts,
      'targetType': targetType,
      'targetId': targetId,
      'visibility': visibility == PollVisibility.secret ? 'secret' : 'public',
    };

    final res = await ApiClient.instance.post('/polls', body: payload);
    return (res is Map<String, dynamic>) ? (res['id'] as String? ?? '') : res.toString();
  }

  Stream<List<Poll>> streamPolls(String parentPath) {
    if (!_pollControllers.containsKey(parentPath) || _pollControllers[parentPath]!.isClosed) {
      _pollControllers[parentPath] = StreamController<List<Poll>>.broadcast();
    }
    return _pollControllers[parentPath]!.stream;
  }

  Stream<List<PollVote>> streamVotes(String parentPath, String pollId) async* {
    try {
      final res = await ApiClient.instance.get('/polls/$pollId');
      if (res is Map<String, dynamic> && res.containsKey('votes')) {
        final votes = (res['votes'] as List)
            .whereType<Map<String, dynamic>>()
            .map(PollVote.fromJson)
            .toList();
        yield votes;
      } else {
        yield <PollVote>[];
      }
    } catch (_) {
      yield <PollVote>[];
    }
  }

  Stream<PollVote?> streamMyVote(String parentPath, String pollId) async* {
    try {
      final res = await ApiClient.instance.get('/polls/$pollId');
      if (res is Map<String, dynamic> && res.containsKey('myVote')) {
        final myVoteIdx = res['myVote'];
        if (myVoteIdx is num) {
          yield PollVote(
            uid: ApiClient.instance.currentUserId ?? '',
            optionIndex: myVoteIdx.toInt(),
          );
          return;
        }
      }
      yield null;
    } catch (_) {
      yield null;
    }
  }

  Future<void> castVote({
    required String parentPath,
    required String pollId,
    required int optionIndex,
  }) async {
    await ApiClient.instance.post('/polls/$pollId/vote', body: {
      'optionIndex': optionIndex,
    });
  }

  Future<void> closePoll(String parentPath, String pollId) async {}
  Future<void> deletePoll(String parentPath, String pollId) async {}
}
