import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Per-chat on-disk cache of decrypted message data.
///
/// Two layers are persisted side-by-side:
///
///  * **Payload cache** — `{msgId: decryptedJsonString}`. Lets
///    [ChatService.streamMessages] skip the AES-GCM decryption for any
///    message we have already opened on this device. Bounded to the last
///    [maxEntries] message ids per chat.
///  * **Snapshot cache** — the most recent rendered `List<ChatMessage>` as
///    JSON. Lets the chat screen render the last [maxEntries] bubbles
///    immediately on open, before Firestore returns its first snapshot.
class MessageCache {
  MessageCache._();
  static final MessageCache instance = MessageCache._();

  static const int maxEntries = 20;

  Directory? _root;
  Future<Directory>? _rootFuture;

  // In-memory mirror of the on-disk payload cache, keyed by chatId. Avoids
  // re-reading the file on every decrypt loop iteration. Populated lazily
  // by [loadPayloads].
  final Map<String, Map<String, String>> _payloads = {};

  // Same idea for the rendered snapshot — held in memory after the first
  // load so back-to-back opens of the same chat skip the disk read.
  final Map<String, List<Map<String, dynamic>>> _snapshots = {};

  Future<Directory> _ensureRoot() {
    if (_root != null) return Future.value(_root);
    return _rootFuture ??= () async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/message_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _root = dir;
      return dir;
    }();
  }

  String _safeId(String chatId) => chatId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<File> _payloadFile(String chatId) async {
    final root = await _ensureRoot();
    return File('${root.path}/${_safeId(chatId)}.payloads.json');
  }

  Future<File> _snapshotFile(String chatId) async {
    final root = await _ensureRoot();
    return File('${root.path}/${_safeId(chatId)}.snapshot.json');
  }

  // ─── Payload cache ─────────────────────────────────────────────

  /// Load the payload map for [chatId]. Subsequent calls return the
  /// in-memory mirror without touching disk.
  Future<Map<String, String>> loadPayloads(String chatId) async {
    final cached = _payloads[chatId];
    if (cached != null) return cached;
    try {
      final f = await _payloadFile(chatId);
      if (!await f.exists()) {
        return _payloads[chatId] = <String, String>{};
      }
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _payloads[chatId] = decoded.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }
    } catch (e) {
      debugPrint('[message-cache] payload load failed for $chatId: $e');
    }
    return _payloads[chatId] = <String, String>{};
  }

  /// Replace the on-disk payload map with [entries], trimmed to the most
  /// recent [maxEntries] ids in insertion order.
  Future<void> savePayloads(
    String chatId,
    Map<String, String> entries,
  ) async {
    final trimmed = _trim(entries);
    _payloads[chatId] = trimmed;
    try {
      final f = await _payloadFile(chatId);
      await f.writeAsString(jsonEncode(trimmed), flush: true);
    } catch (e) {
      debugPrint('[message-cache] payload save failed for $chatId: $e');
    }
  }

  Map<String, String> _trim(Map<String, String> entries) {
    if (entries.length <= maxEntries) return Map<String, String>.from(entries);
    final keys = entries.keys.toList();
    final keep = keys.sublist(keys.length - maxEntries);
    return {for (final k in keep) k: entries[k]!};
  }

  // ─── Snapshot cache ────────────────────────────────────────────

  /// Most recent rendered snapshot for [chatId], or `null` if none.
  Future<List<Map<String, dynamic>>?> loadSnapshot(String chatId) async {
    final cached = _snapshots[chatId];
    if (cached != null) return cached;
    try {
      final f = await _snapshotFile(chatId);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        return _snapshots[chatId] = list;
      }
    } catch (e) {
      debugPrint('[message-cache] snapshot load failed for $chatId: $e');
    }
    return null;
  }

  /// Persist [snapshot] (already trimmed to last [maxEntries]) for [chatId].
  Future<void> saveSnapshot(
    String chatId,
    List<Map<String, dynamic>> snapshot,
  ) async {
    final trimmed = snapshot.length <= maxEntries
        ? snapshot
        : snapshot.sublist(snapshot.length - maxEntries);
    _snapshots[chatId] = trimmed;
    try {
      final f = await _snapshotFile(chatId);
      await f.writeAsString(jsonEncode(trimmed), flush: true);
    } catch (e) {
      debugPrint('[message-cache] snapshot save failed for $chatId: $e');
    }
  }

  /// Drop everything cached for [chatId] (memory + disk). Used when a chat
  /// is deleted/left so we don't keep stale plaintext around.
  Future<void> clear(String chatId) async {
    _payloads.remove(chatId);
    _snapshots.remove(chatId);
    try {
      final p = await _payloadFile(chatId);
      if (await p.exists()) await p.delete();
      final s = await _snapshotFile(chatId);
      if (await s.exists()) await s.delete();
    } catch (e) {
      debugPrint('[message-cache] clear failed for $chatId: $e');
    }
  }

  /// Wipe every cached chat on this device. Called on sign-out so the
  /// next user on the same device can't see plaintext from the previous
  /// account.
  Future<void> clearAll() async {
    _payloads.clear();
    _snapshots.clear();
    try {
      final root = await _ensureRoot();
      if (!await root.exists()) return;
      await for (final entry in root.list()) {
        if (entry is File) {
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[message-cache] clearAll failed: $e');
    }
  }
}
