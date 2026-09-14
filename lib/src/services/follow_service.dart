import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'user_service.dart';

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

      _followersMap.putIfAbsent(targetUid, () => {}).add(currentUid);
      _followersControllers[targetUid]?.add(_followersMap[targetUid]!.toList());

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

      _followersMap[targetUid]?.remove(currentUid);
      _followersControllers[targetUid]?.add(_followersMap[targetUid]?.toList() ?? []);

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
  }) async* {
    if (currentUid == targetUid) {
      yield false;
      return;
    }
    final key = '${currentUid}_$targetUid';
    if (!_isFollowingControllers.containsKey(key) || _isFollowingControllers[key]!.isClosed) {
      _isFollowingControllers[key] = StreamController<bool>.broadcast();
    }

    if (_isFollowingState.containsKey(key)) {
      yield _isFollowingState[key]!;
    }

    try {
      final res = await ApiClient.instance.get('/users/$targetUid/follow-status');
      if (res is Map<String, dynamic> && res.containsKey('isFollowing')) {
        final isF = res['isFollowing'] == true;
        _isFollowingState[key] = isF;
        yield isF;
      } else if (!_isFollowingState.containsKey(key)) {
        yield false;
      }
    } catch (_) {
      if (!_isFollowingState.containsKey(key)) {
        yield false;
      }
    }

    yield* _isFollowingControllers[key]!.stream;
  }

  Stream<bool> hasRequestedFollow({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return Stream.value(false);
  }

  Stream<List<String>> getFollowing(String uid) async* {
    if (!_followingControllers.containsKey(uid) || _followingControllers[uid]!.isClosed) {
      _followingControllers[uid] = StreamController<List<String>>.broadcast();
    }

    // Always emit current cached state immediately so stream consumers don't hang
    if (_followingMap.containsKey(uid)) {
      yield _followingMap[uid]!.toList();
    }

    // Refresh from backend API
    try {
      final res = await ApiClient.instance.get('/users/$uid/following');
      final uids = <String>[];
      final List items = res is List
          ? res
          : (res is Map<String, dynamic> && res['data'] is List)
              ? res['data'] as List
              : const [];

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString() ?? item['uid']?.toString() ?? '';
          if (id.isNotEmpty) {
            uids.add(id);
            UserService().cacheUser(id, item);
          }
        }
      }

      _followingMap[uid] = uids.toSet();
      yield uids;
    } catch (e) {
      debugPrint('[FollowService] getFollowing error: $e');
      if (!_followingMap.containsKey(uid)) {
        yield const <String>[];
      }
    }

    yield* _followingControllers[uid]!.stream;
  }

  Stream<List<String>> getFollowers(String uid) async* {
    if (!_followersControllers.containsKey(uid) || _followersControllers[uid]!.isClosed) {
      _followersControllers[uid] = StreamController<List<String>>.broadcast();
    }

    // Always emit current cached state immediately so stream consumers don't hang
    if (_followersMap.containsKey(uid)) {
      yield _followersMap[uid]!.toList();
    }

    // Refresh from backend API
    try {
      final res = await ApiClient.instance.get('/users/$uid/followers');
      final uids = <String>[];
      final List items = res is List
          ? res
          : (res is Map<String, dynamic> && res['data'] is List)
              ? res['data'] as List
              : const [];

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString() ?? item['uid']?.toString() ?? '';
          if (id.isNotEmpty) {
            uids.add(id);
            UserService().cacheUser(id, item);
          }
        }
      }

      _followersMap[uid] = uids.toSet();
      yield uids;
    } catch (e) {
      debugPrint('[FollowService] getFollowers error: $e');
      if (!_followersMap.containsKey(uid)) {
        yield const <String>[];
      }
    }

    yield* _followersControllers[uid]!.stream;
  }

  Stream<List<String>> getFollowRequests(String uid) {
    return Stream.value(const []);
  }
}
