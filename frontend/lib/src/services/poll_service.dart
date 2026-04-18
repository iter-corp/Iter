import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// A poll's visibility semantics:
/// - public: voter identities are visible to everyone.
/// - secret: only aggregated counts are shown; who voted what is hidden.
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

  factory Poll.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Poll(
      id: doc.id,
      question: (d['question'] as String?) ?? '',
      options: ((d['options'] as List?) ?? const []).cast<String>(),
      createdByUid: (d['createdByUid'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      visibility: _visFrom(d['visibility'] as String?),
      closed: (d['closed'] as bool?) ?? false,
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

  factory PollVote.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PollVote(
      uid: doc.id,
      optionIndex: (d['optionIndex'] as num?)?.toInt() ?? -1,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Polls live as a subcollection of whatever "chat room" they belong to:
///   {parentPath}/polls/{pollId}
///   {parentPath}/polls/{pollId}/votes/{voterUid}
///
/// parentPath example:
///   - "chats/{chatId}"        (1:1 chat)
///   - "eventChats/{eventId}"  (event group)
class PollService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _pollsCol(String parentPath) =>
      _db.collection('$parentPath/polls');

  CollectionReference<Map<String, dynamic>> _votesCol(
    String parentPath,
    String pollId,
  ) =>
      _db.collection('$parentPath/polls/$pollId/votes');

  Future<String> createPoll({
    required String parentPath,
    required String question,
    required List<String> options,
    required PollVisibility visibility,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final cleanOpts = options
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .take(10)
        .toList();
    if (question.trim().isEmpty || cleanOpts.length < 2) {
      throw Exception('Need a question and at least 2 options');
    }
    final ref = await _pollsCol(parentPath).add({
      'question': question.trim(),
      'options': cleanOpts,
      'createdByUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'visibility':
          visibility == PollVisibility.secret ? 'secret' : 'public',
      'closed': false,
    });
    return ref.id;
  }

  Stream<List<Poll>> streamPolls(String parentPath) {
    return _pollsCol(parentPath)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Poll.fromDoc).toList());
  }

  Stream<List<PollVote>> streamVotes(String parentPath, String pollId) {
    return _votesCol(parentPath, pollId)
        .snapshots()
        .map((s) => s.docs.map(PollVote.fromDoc).toList());
  }

  Stream<PollVote?> streamMyVote(String parentPath, String pollId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _votesCol(parentPath, pollId)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists ? PollVote.fromDoc(s) : null);
  }

  Future<void> castVote({
    required String parentPath,
    required String pollId,
    required int optionIndex,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _votesCol(parentPath, pollId).doc(user.uid).set({
      'optionIndex': optionIndex,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> closePoll(String parentPath, String pollId) async {
    await _pollsCol(parentPath).doc(pollId).update({'closed': true});
  }

  Future<void> deletePoll(String parentPath, String pollId) async {
    await _pollsCol(parentPath).doc(pollId).delete();
  }
}
