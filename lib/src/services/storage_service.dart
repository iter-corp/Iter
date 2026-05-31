import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class StorageException implements Exception {
  StorageException(this.message);
  final String message;
  @override
  String toString() => 'StorageException: $message';
}

class StorageService {
  StorageService();

  String get _supabaseUrl => _requireEnv('SUPABASE_URL');
  String get _anonKey => _requireEnv('SUPABASE_ANON_KEY');

  /// Reads a required env var, throwing a clear error if it's missing or empty.
  ///
  /// `dotenv.env[key]!` returns an *empty string* (not null) when the key is
  /// absent, so a bare `!` doesn't protect against a `.env` that failed to
  /// load — instead the empty URL later produces a cryptic "No host specified
  /// in URI" error. This makes the real cause explicit.
  String _requireEnv(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StorageException(
          '$key is not configured. The .env file may have failed to load — '
          'try a clean rebuild (flutter clean).');
    }
    return value;
  }

  Future<String> uploadAvatar(File file) {
    return _uploadViaEdge(bucket: 'avatars', file: file, kind: 'avatar');
  }

  Future<String> uploadCover(File file) {
    return _uploadViaEdge(bucket: 'avatars', file: file, kind: 'cover');
  }

  Future<String> uploadPostImage(File file) {
    return _uploadViaEdge(bucket: 'posts', file: file, kind: 'post');
  }

  Future<String> uploadPostVideo(File file) {
    return _uploadViaEdge(bucket: 'posts', file: file, kind: 'post-video');
  }

  Future<String> uploadChatImage(File file, String chatId) {
    return _uploadViaEdge(bucket: 'posts', file: file, kind: 'chat', subPath: chatId);
  }

  Future<String> uploadChatAudio(File file, String chatId) {
    return _uploadViaEdge(
        bucket: 'posts', file: file, kind: 'audio', subPath: chatId);
  }

  Future<String> uploadStoryImage(File file) {
    return _uploadViaEdge(bucket: 'posts', file: file, kind: 'story');
  }

  /// Video attached to a story.
  ///
  /// Tries the dedicated `story-video` kind first (paths under
  /// `stories/videos/`). Older deployments of the `issue-upload-url`
  /// edge function don't whitelist that kind yet and would return
  /// `{"error":"bad kind"}` → we fall back to `post-video` (paths under
  /// `posts/videos/`). The video bytes and public URL are valid either
  /// way; only the storage path differs.
  Future<String> uploadStoryVideo(File file) async {
    try {
      return await _uploadViaEdge(
        bucket: 'posts',
        file: file,
        kind: 'story-video',
      );
    } on StorageException catch (e) {
      if (e.message.contains('bad kind')) {
        debugPrint(
            '[StorageService] story-video kind rejected; falling back to post-video');
        return _uploadViaEdge(
          bucket: 'posts',
          file: file,
          kind: 'post-video',
        );
      }
      rethrow;
    }
  }

  /// Video attached to a chat message.
  Future<String> uploadChatVideo(File file, String chatId) {
    return _uploadViaEdge(
        bucket: 'posts', file: file, kind: 'chat-video', subPath: chatId);
  }

  /// Generic file attachment (PDF, doc, etc.) uploaded to a chat.
  Future<String> uploadChatFile(File file, String chatId) {
    return _uploadViaEdge(
        bucket: 'posts', file: file, kind: 'chat-file', subPath: chatId);
  }

  /// Permanently deletes EVERY media file the signed-in user has uploaded
  /// (avatars, covers, post images/videos, story media, chat images/videos/
  /// files/voices) from Supabase Storage. Used by account self-delete so no
  /// media is left behind. Best-effort: throws [StorageException] on failure
  /// so the caller can decide whether to surface it, but the deletion of the
  /// user's Firestore data should proceed regardless.
  ///
  /// Calls the `delete-user-media` edge function, which verifies the Firebase
  /// ID token server-side and removes only `<uid>/...` paths — a user can
  /// never delete another user's files.
  Future<void> deleteAllMyMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StorageException('Not signed in');

    final idToken = await user.getIdToken();
    if (idToken == null) {
      throw StorageException('Could not get Firebase ID token');
    }

    final edgeUri = Uri.parse('$_supabaseUrl/functions/v1/delete-user-media');
    http.Response res;
    try {
      res = await http
          .post(
            edgeUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_anonKey',
              'apikey': _anonKey,
              'X-Firebase-Token': idToken,
            },
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw StorageException('Media deletion timed out.');
    }

    if (res.statusCode != 200) {
      throw StorageException(
          'delete-user-media failed: ${res.statusCode} ${res.body}');
    }
    debugPrint('[StorageService] deleteAllMyMedia OK: ${res.body}');
  }

  Future<String> _uploadViaEdge({
    required String bucket,
    required File file,
    required String kind,
    String? subPath,
  }) async {
    debugPrint('[StorageService] _uploadViaEdge start '
        'bucket=$bucket kind=$kind subPath=$subPath path=${file.path}');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[StorageService] ABORT: no Firebase user');
      throw StorageException('Not signed in');
    }
    debugPrint('[StorageService] firebase uid=${user.uid}');

    final idToken = await user.getIdToken();
    if (idToken == null) {
      debugPrint('[StorageService] ABORT: getIdToken returned null');
      throw StorageException('Could not get Firebase ID token');
    }
    debugPrint('[StorageService] got Firebase ID token (len=${idToken.length})');

    final exists = await file.exists();
    final size = exists ? await file.length() : -1;
    debugPrint('[StorageService] file exists=$exists size=$size bytes');
    if (!exists) {
      throw StorageException('File not found at ${file.path}');
    }
    if (size == 0) {
      throw StorageException('File is empty: ${file.path}');
    }

    final ext = _extensionOf(file.path);
    final contentType = _contentTypeOf(ext);
    debugPrint('[StorageService] ext=$ext contentType=$contentType');
    // NOTE: do NOT relabel `m4a` -> `aac` here. The recorder writes an MP4/AAC
    // container (`.m4a`); naming the stored object `.aac` makes iOS/Android
    // audio players treat it as a raw ADTS AAC stream, which they can't decode
    // from the MP4 bytes — playback is silent and reports "complete" instantly.
    // The edge function already whitelists `m4a`, so the real extension works.

    final edgeUri = Uri.parse('$_supabaseUrl/functions/v1/issue-upload-url');
    debugPrint('[StorageService] POST $edgeUri');

    final reqBody = jsonEncode({
      'bucket': bucket,
      'kind': kind,
      'ext': ext,
      if (subPath != null) 'subPath': subPath,
    });
    debugPrint('[StorageService] request body=$reqBody');

    http.Response req;
    try {
      req = await http
          .post(
            edgeUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_anonKey',
              'apikey': _anonKey,
              'X-Firebase-Token': idToken,
            },
            body: reqBody,
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw StorageException('Upload setup timed out. Please try again.');
    } catch (e, st) {
      debugPrint('[StorageService] issue-upload-url network error: $e\n$st');
      rethrow;
    }

    debugPrint('[StorageService] issue-upload-url status=${req.statusCode} '
        'body=${req.body}');

    if (req.statusCode != 200) {
      throw StorageException(
          'issue-upload-url failed: ${req.statusCode} ${req.body}');
    }

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final uploadUrl = data['uploadUrl'] as String;
    final publicUrl = data['publicUrl'] as String;
    final token = data['token'] as String?;
    debugPrint('[StorageService] uploadUrl=$uploadUrl');
    debugPrint('[StorageService] publicUrl=$publicUrl');
    debugPrint('[StorageService] token present=${token != null}');

    debugPrint('[StorageService] reading file bytes…');
    final bytes = await file.readAsBytes();
    debugPrint('[StorageService] read ${bytes.length} bytes; PUT to storage');

    http.Response upload;
    try {
      upload = await http
          .put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Type': contentType,
              if (token != null) 'Authorization': 'Bearer $token',
              'x-upsert': 'true',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw StorageException(
          'Upload timed out. Try a smaller file or a stronger connection.');
    } catch (e, st) {
      debugPrint('[StorageService] PUT upload network error: $e\n$st');
      rethrow;
    }

    debugPrint('[StorageService] PUT upload status=${upload.statusCode} '
        'body=${upload.body}');

    if (upload.statusCode != 200 && upload.statusCode != 201) {
      throw StorageException(
          'upload failed: ${upload.statusCode} ${upload.body}');
    }

    debugPrint('[StorageService] SUCCESS publicUrl=$publicUrl');
    return publicUrl;
  }

  String _extensionOf(String path) {
    final i = path.lastIndexOf('.');
    if (i == -1) return 'bin';
    return path.substring(i + 1).toLowerCase();
  }

  String _contentTypeOf(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'm4a':
        // MP4/AAC container (what AudioRecorder writes). `audio/mp4` is the
        // standard, widely-decodable type; `audio/m4a` is non-standard and
        // some players reject it.
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
