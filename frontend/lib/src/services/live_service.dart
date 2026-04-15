import 'package:cloud_firestore/cloud_firestore.dart';

class LiveStream {
  final String id;
  final String hostUid;
  final String title;
  final String? appId;
  final String? token;
  final bool isActive;
  final int viewersCount;
  final DateTime startedAt;

  const LiveStream({
    required this.id,
    required this.hostUid,
    required this.title,
    this.appId,
    this.token,
    required this.isActive,
    required this.viewersCount,
    required this.startedAt,
  });

  factory LiveStream.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return LiveStream(
      id: doc.id,
      hostUid: d['hostUid'] as String? ?? '',
      title: d['title'] as String? ?? '',
      appId: d['appId'] as String?,
      token: d['token'] as String?,
      isActive: d['isActive'] as bool? ?? false,
      viewersCount: (d['viewersCount'] as int?) ?? 0,
      startedAt: (d['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class LiveService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('liveStreams');

  /// Start a new live stream. Returns the newly created [LiveStream].
  Future<LiveStream> startStream({
    required String hostUid,
    required String title,
  }) async {
    final ref = _col.doc();
    await ref.set({
      'hostUid': hostUid,
      'title': title,
      'isActive': true,
      'viewersCount': 0,
      'token': null,
      'startedAt': FieldValue.serverTimestamp(),
    });

    final snap = await ref.get();
    return LiveStream.fromDoc(snap);
  }

  /// End a live stream.
  Future<void> endStream(String streamId) async {
    await _col.doc(streamId).update({'isActive': false});
  }

  /// Stream all currently active live streams.
  Stream<List<LiveStream>> getActiveStreams() {
    return _col
        .where('isActive', isEqualTo: true)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(LiveStream.fromDoc).toList());
  }

  /// Join an existing stream as a viewer. Returns the [LiveStream] with token.
  Future<LiveStream> joinStream(String streamId) async {
    // Increment viewer count
    await _col.doc(streamId).update({
      'viewersCount': FieldValue.increment(1),
    });

    final snap = await _col.doc(streamId).get();
    return LiveStream.fromDoc(snap);
  }

  /// Decrement viewer count when a viewer leaves.
  Future<void> leaveStream(String streamId) async {
    await _col.doc(streamId).update({
      'viewersCount': FieldValue.increment(-1),
    });
  }
}
