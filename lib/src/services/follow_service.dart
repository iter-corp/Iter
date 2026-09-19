import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'api_client.dart';
import 'user_service.dart';

class FollowService {
  static final FollowService _instance = FollowService._internal();
  factory FollowService() => _instance;
  FollowService._internal();

  final Map<String, Set<String>> _followingMap = {};
  final Map<String, Set<String>> _followersMap = {};
  final Map<String, BehaviorSubject<List<String>>> _followingSubjects = {};
  final Map<String, BehaviorSubject<List<String>>> _followersSubjects = {};
  final Map<String, BehaviorSubject<List<String>>> _followRequestsSubjects = {};

  final Map<String, BehaviorSubject<bool>> _isFollowingSubjects = {};
  final Map<String, bool> _isFollowingState = {};
  final Map<String, BehaviorSubject<bool>> _hasRequestedFollowSubjects = {};
  final Map<String, bool> _hasRequestedFollowState = {};

  Future<void> follow({
    required String currentUid,
    required String targetUid,
    required bool isPrivate,
  }) async {
    if (currentUid == targetUid) return;

    try {
      final res = await ApiClient.instance.post('/users/$targetUid/follow');
      final status = (res is Map<String, dynamic>)
          ? res['status']
          : (isPrivate ? 'pending' : 'active');
      final isPending = status == 'pending';
      final isActive = status == 'active';

      if (isActive) {
        _followingMap.putIfAbsent(currentUid, () => {}).add(targetUid);
        _followingSubjects[currentUid]?.add(_followingMap[currentUid]!.toList());

        _followersMap.putIfAbsent(targetUid, () => {}).add(currentUid);
        _followersSubjects[targetUid]?.add(_followersMap[targetUid]!.toList());
      }

      final key = '${currentUid}_$targetUid';
      _isFollowingState[key] = isActive;
      _isFollowingSubjects[key]?.add(isActive);

      _hasRequestedFollowState[key] = isPending;
      _hasRequestedFollowSubjects[key]?.add(isPending);

      // Refresh user profiles so followersCount & followingCount counters stay in sync
      UserService().getUser(currentUid);
      UserService().getUser(targetUid);
    } catch (e) {
      debugPrint('[FollowService] follow error: $e');
      rethrow;
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
      _followingSubjects[currentUid]
          ?.add(_followingMap[currentUid]?.toList() ?? []);

      _followersMap[targetUid]?.remove(currentUid);
      _followersSubjects[targetUid]
          ?.add(_followersMap[targetUid]?.toList() ?? []);

      final key = '${currentUid}_$targetUid';
      _isFollowingState[key] = false;
      _isFollowingSubjects[key]?.add(false);

      _hasRequestedFollowState[key] = false;
      _hasRequestedFollowSubjects[key]?.add(false);

      UserService().getUser(currentUid);
      UserService().getUser(targetUid);
    } catch (e) {
      debugPrint('[FollowService] unfollow error: $e');
      rethrow;
    }
  }

  Future<void> acceptFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    try {
      await ApiClient.instance
          .post('/users/$currentUid/follow-requests/$requesterUid/accept');

      _followersMap.putIfAbsent(currentUid, () => {}).add(requesterUid);
      _followersSubjects[currentUid]?.add(_followersMap[currentUid]!.toList());

      _followingMap.putIfAbsent(requesterUid, () => {}).add(currentUid);
      _followingSubjects[requesterUid]?.add(_followingMap[requesterUid]!.toList());

      refreshFollowRequests(currentUid);
      UserService().getUser(currentUid);
      UserService().getUser(requesterUid);
    } catch (e) {
      debugPrint('[FollowService] acceptFollowRequest error: $e');
      rethrow;
    }
  }

  Future<void> rejectFollowRequest({
    required String currentUid,
    required String requesterUid,
  }) async {
    try {
      await ApiClient.instance
          .post('/users/$currentUid/follow-requests/$requesterUid/reject');
      refreshFollowRequests(currentUid);
    } catch (e) {
      debugPrint('[FollowService] rejectFollowRequest error: $e');
      rethrow;
    }
  }

  Stream<bool> isFollowing({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    final key = '${currentUid}_$targetUid';

    if (!_isFollowingSubjects.containsKey(key) ||
        _isFollowingSubjects[key]!.isClosed) {
      final initial = _isFollowingState[key] ?? false;
      _isFollowingSubjects[key] = BehaviorSubject<bool>.seeded(initial);
    }

    // Refresh state asynchronously from user profile
    ApiClient.instance.get('/users/$targetUid').then((res) {
      if (res is Map<String, dynamic>) {
        if (res.containsKey('isFollowing')) {
          final isF = res['isFollowing'] == true;
          _isFollowingState[key] = isF;
          if (!(_isFollowingSubjects[key]?.isClosed ?? true)) {
            _isFollowingSubjects[key]?.add(isF);
          }
        }
        if (res.containsKey('isPending')) {
          final isP = res['isPending'] == true;
          _hasRequestedFollowState[key] = isP;
          if (!(_hasRequestedFollowSubjects[key]?.isClosed ?? true)) {
            _hasRequestedFollowSubjects[key]?.add(isP);
          }
        }
      }
    }).catchError((_) {});

    return _isFollowingSubjects[key]!.stream;
  }

  Stream<bool> hasRequestedFollow({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    final key = '${currentUid}_$targetUid';

    if (!_hasRequestedFollowSubjects.containsKey(key) ||
        _hasRequestedFollowSubjects[key]!.isClosed) {
      final initial = _hasRequestedFollowState[key] ?? false;
      _hasRequestedFollowSubjects[key] = BehaviorSubject<bool>.seeded(initial);
    }

    return _hasRequestedFollowSubjects[key]!.stream;
  }

  Stream<List<String>> getFollowing(String uid) {
    if (!_followingSubjects.containsKey(uid) ||
        _followingSubjects[uid]!.isClosed) {
      final cached = _followingMap[uid]?.toList() ?? const <String>[];
      _followingSubjects[uid] = BehaviorSubject<List<String>>.seeded(cached);
    }

    refreshFollowing(uid);
    return _followingSubjects[uid]!.stream;
  }

  Future<void> refreshFollowing(String uid) async {
    try {
      final res = await ApiClient.instance.get('/users/$uid/following');
      final list = <String>[];
      final dynamic raw = res is Map<String, dynamic> && res.containsKey('data')
          ? res['data']
          : res;

      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final id = (item['id'] ?? item['uid'])?.toString();
            if (id != null && id.isNotEmpty) {
              list.add(id);
              if (item is Map<String, dynamic>) {
                UserService().cacheUser(id, item);
              }
            }
          } else if (item != null) {
            list.add(item.toString());
          }
        }
        _followingMap[uid] = list.toSet();
        if (!(_followingSubjects[uid]?.isClosed ?? true)) {
          _followingSubjects[uid]?.add(list);
        }
      }
    } catch (e) {
      debugPrint('[FollowService] refreshFollowing error for $uid: $e');
    }
  }

  Stream<List<String>> getFollowers(String uid) {
    if (!_followersSubjects.containsKey(uid) ||
        _followersSubjects[uid]!.isClosed) {
      final cached = _followersMap[uid]?.toList() ?? const <String>[];
      _followersSubjects[uid] = BehaviorSubject<List<String>>.seeded(cached);
    }

    refreshFollowers(uid);
    return _followersSubjects[uid]!.stream;
  }

  Future<void> refreshFollowers(String uid) async {
    try {
      final res = await ApiClient.instance.get('/users/$uid/followers');
      if (res is List) {
        final list = res.map((e) => e.toString()).toList();
        _followersMap[uid] = list.toSet();
        if (!(_followersSubjects[uid]?.isClosed ?? true)) {
          _followersSubjects[uid]?.add(list);
        }
      }
    } catch (e) {
      debugPrint('[FollowService] refreshFollowers error for $uid: $e');
    }
  }

  Stream<List<String>> getFollowRequests(String uid) {
    if (!_followRequestsSubjects.containsKey(uid) ||
        _followRequestsSubjects[uid]!.isClosed) {
      _followRequestsSubjects[uid] =
          BehaviorSubject<List<String>>.seeded(const []);
    }

    refreshFollowRequests(uid);
    return _followRequestsSubjects[uid]!.stream;
  }

  Future<void> refreshFollowRequests(String uid) async {
    try {
      final res = await ApiClient.instance.get('/users/$uid/follow-requests');
      if (res is List) {
        final list = res.map((e) => e.toString()).toList();
        if (!(_followRequestsSubjects[uid]?.isClosed ?? true)) {
          _followRequestsSubjects[uid]?.add(list);
        }
      }
    } catch (e) {
      debugPrint('[FollowService] refreshFollowRequests error for $uid: $e');
    }
  }
}
