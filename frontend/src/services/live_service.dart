import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  final _functions = FirebaseFunctions.instance;

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
    // Request Agora token from Cloud Function (no-op if not deployed yet)
    try {
      final result = await _functions
          .httpsCallable('issueLiveToken')
          .call({'channelName': ref.id, 'role': 'host'});
      final token = result.data['token'] as String?;
      final appId = result.data['appId'] as String?;
      if (token != null) {
        await ref.update({'token': token, if (appId != null) 'appId': appId});
      } else if (appId != null) {
        await ref.update({'appId': appId});
      }
    } catch (_) {
      // Cloud Function not yet deployed — proceed without token
    }
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

    // Request a viewer token from Cloud Function
    String? token;
    String? appId;
    try {
      final result = await _functions
          .httpsCallable('issueLiveToken')
          .call({'channelName': streamId, 'role': 'audience'});
      token = result.data['token'] as String?;
      appId = result.data['appId'] as String?;
    } catch (_) {
      // Cloud Function not yet deployed
    }

    final snap = await _col.doc(streamId).get();
    final stream = LiveStream.fromDoc(snap);
    // Return with the fetched token if different from stored
    return token != null
        ? LiveStream(
            id: stream.id,
            hostUid: stream.hostUid,
            title: stream.title,
            appId: appId ?? stream.appId,
            token: token,
            isActive: stream.isActive,
            viewersCount: stream.viewersCount,
            startedAt: stream.startedAt,
          )
        : stream;
  }

  /// Decrement viewer count when a viewer leaves.
  Future<void> leaveStream(String streamId) async {
    await _col.doc(streamId).update({
      'viewersCount': FieldValue.increment(-1),
    });
  }
}
