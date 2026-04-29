import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
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

  String get _supabaseUrl => dotenv.env['SUPABASE_URL']!;
  String get _anonKey => dotenv.env['SUPABASE_ANON_KEY']!;

  Future<String> uploadAvatar(File file) {
    return _uploadViaEdge(bucket: 'avatars', file: file, kind: 'avatar');
  }

  Future<String> uploadCover(File file) {
    return _uploadViaEdge(bucket: 'avatars', file: file, kind: 'cover');
  }

  Future<String> uploadPostImage(File file) {
    return _uploadViaEdge(bucket: 'posts', file: file, kind: 'post');
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

  Future<String> _uploadViaEdge({
    required String bucket,
    required File file,
    required String kind,
    String? subPath,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StorageException('Not signed in');

    final idToken = await user.getIdToken();
    if (idToken == null) throw StorageException('Could not get Firebase ID token');

    var ext = _extensionOf(file.path);
    final contentType = _contentTypeOf(ext);
    // The Supabase edge function (issue-upload-url) rejects `m4a` with
    // {"error":"bad ext"} even though the file is plain AAC audio inside an
    // MP4 container. Re-label as `aac` for the upload-URL request — the
    // bytes are still valid AAC so playback is unaffected.
    if (kind == 'audio' && ext == 'm4a') {
      ext = 'aac';
    }

    final edgeUri = Uri.parse('$_supabaseUrl/functions/v1/issue-upload-url');

    final req = await http.post(
      edgeUri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_anonKey',
        'apikey': _anonKey,
        'X-Firebase-Token': idToken,
      },
      body: jsonEncode({
        'bucket': bucket,
        'kind': kind,
        'ext': ext,
        if (subPath != null) 'subPath': subPath,
      }),
    );

    if (req.statusCode != 200) {
      throw StorageException('issue-upload-url failed: ${req.statusCode} ${req.body}');
    }

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final uploadUrl = data['uploadUrl'] as String;
    final publicUrl = data['publicUrl'] as String;
    final token = data['token'] as String?;

    final bytes = await file.readAsBytes();
    final upload = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Type': contentType,
        if (token != null) 'Authorization': 'Bearer $token',
        'x-upsert': 'true',
      },
      body: bytes,
    );

    if (upload.statusCode != 200 && upload.statusCode != 201) {
      throw StorageException('upload failed: ${upload.statusCode} ${upload.body}');
    }

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
      case 'aac':
        return 'audio/m4a';
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
