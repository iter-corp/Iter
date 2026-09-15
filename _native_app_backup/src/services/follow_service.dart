import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class FollowService {
  static final FollowService _instance = FollowService._internal();
  factory FollowService() => _instance;
  FollowService._internal();

  final Map<String, Set<String>> _followingMap = {};
  final Map<String, Set<String>> _followersMap = {};
  final Map<String, StreamController<List<String>>> _followingControllers = {};
  final Map<String, StreamController<List<String>>> _followersControllers = {};

  final Map<String, StreamController<bool>> _isFollowingControllers = {};
  final Map<String, bool> _isFollowingState = {};

  Future<void> follow({
    required String currentUid,
    required String targetUid,
    required bool isPrivate,
  }) async {
    if (currentUid == targetUid) return;

    try {
      await ApiClient.instance.post('/users/$targetUid/follow');

      _followingMap.putIfAbsent(currentUid, () => {}).add(targetUid);
      _followingControllers[currentUid]?.add(_followingMap[currentUid]!.toList());

      final key = '${currentUid}_$targetUid';
      _isFollowingState[key] = !isPrivate;
      _isFollowingControllers[key]?.add(!isPrivate);
    } catch (e) {
      debugPrint('[FollowService] follow error: $e');
    }
  }

  Future<void> unfollow({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    try {
      await ApiClient.instance.delete('/users/$targetUid/follow');

      _followingMap[currentUid]?.remove(targetUid);
      _followingControllers[currentUid]?.add(_followingMap[currentUid]?.toList() ?? []);

      final key = '${currentUid}_$targetUid';
      _isFollowingState[key] = false;
      _isFollowingControllers[key]?.add(false);
    } catch (e) {
      debugPrint('[FollowService] unfollow error: $e');
    }
  }

  Future<void> acceptFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    await follow(currentUid: currentUid, targetUid: requesterUid, isPrivate: false);
  }

  Future<void> rejectFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    await unfollow(currentUid: requesterUid, targetUid: currentUid);
  }

  Stream<bool> isFollowing({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    final key = '${currentUid}_$targetUid';

    if (!_isFollowingControllers.containsKey(key) || _isFollowingControllers[key]!.isClosed) {
      _isFollowingControllers[key] = StreamController<bool>.broadcast();
    }

    if (_isFollowingState.containsKey(key)) {
      Timer.run(() => _isFollowingControllers[key]?.add(_isFollowingState[key]!));
    }

    // Refresh state asynchronously from user profile
    ApiClient.instance.get('/users/$targetUid').then((res) {
      if (res is Map<String, dynamic> && res.containsKey('isFollowing')) {
        final isF = res['isFollowing'] == true;
        _isFollowingState[key] = isF;
        _isFollowingControllers[key]?.add(isF);
      }
    }).catchError((_) {});

    return _isFollowingControllers[key]!.stream;
  }

  Stream<bool> hasRequestedFollow({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return Stream.value(false);
  }

  Stream<List<String>> getFollowing(String uid) {
    if (!_followingControllers.containsKey(uid) || _followingControllers[uid]!.isClosed) {
      _followingControllers[uid] = StreamController<List<String>>.broadcast();
    }

    if (_followingMap.containsKey(uid)) {
      Timer.run(() => _followingControllers[uid]?.add(_followingMap[uid]!.toList()));
    }

    return _followingControllers[uid]!.stream;
  }

  Stream<List<String>> getFollowers(String uid) {
    if (!_followersControllers.containsKey(uid) || _followersControllers[uid]!.isClosed) {
      _followersControllers[uid] = StreamController<List<String>>.broadcast();
    }

    if (_followersMap.containsKey(uid)) {
      Timer.run(() => _followersControllers[uid]?.add(_followersMap[uid]!.toList()));
    }

    return _followersControllers[uid]!.stream;
  }

  Stream<List<String>> getFollowRequests(String uid) {
    return Stream.value(const []);
  }
}
