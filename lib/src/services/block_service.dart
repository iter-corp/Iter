import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'api_client.dart';

class BlockService {
  static final BlockService _instance = BlockService._internal();
  factory BlockService() => _instance;
  BlockService._internal();

  final Map<String, Set<String>> _blockedMap = {};
  final Map<String, BehaviorSubject<List<String>>> _blockedSubjects = {};

  Future<void> blockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    try {
      await ApiClient.instance.post('/users/$targetUid/block');
      _blockedMap.putIfAbsent(currentUid, () => {}).add(targetUid);
      _blockedSubjects[currentUid]?.add(_blockedMap[currentUid]!.toList());
    } catch (e) {
      debugPrint('[BlockService] blockUser error: $e');
    }
  }

  Future<void> unblockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;

    try {
      await ApiClient.instance.delete('/users/$targetUid/block');
      _blockedMap[currentUid]?.remove(targetUid);
      _blockedSubjects[currentUid]
          ?.add(_blockedMap[currentUid]?.toList() ?? []);
    } catch (e) {
      debugPrint('[BlockService] unblockUser error: $e');
    }
  }

  Stream<bool> isBlocked({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    final blocked = _blockedMap[currentUid]?.contains(targetUid) ?? false;
    return Stream.value(blocked);
  }

  Stream<bool> isBlockedBy({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid == targetUid) return Stream.value(false);
    return Stream.value(false);
  }

  Stream<List<String>> getBlockedUsers(String uid) {
    if (!_blockedSubjects.containsKey(uid) || _blockedSubjects[uid]!.isClosed) {
      final initial = _blockedMap[uid]?.toList() ?? const <String>[];
      _blockedSubjects[uid] = BehaviorSubject<List<String>>.seeded(initial);
    }
    return _blockedSubjects[uid]!.stream;
  }
}
