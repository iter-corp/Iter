import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class StorageException implements Exception {
  StorageException(this.message);
  final String message;
  @override
  String toString() => 'StorageException: $message';
}

class StorageService {
  StorageService();

  Future<String> uploadAvatar(File file) {
    return _uploadViaBackend(bucket: 'avatars', file: file, kind: 'avatar');
  }

  Future<String> uploadCover(File file) {
    return _uploadViaBackend(bucket: 'avatars', file: file, kind: 'cover');
  }

  Future<String> uploadPostImage(File file) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'post');
  }

  Future<String> uploadPostVideo(File file) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'post-video');
  }

  Future<String> uploadChatImage(File file, String chatId) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'chat', subPath: chatId);
  }

  Future<String> uploadChatAudio(File file, String chatId) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'audio', subPath: chatId);
  }

  Future<String> uploadStoryImage(File file) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'story');
  }

  Future<String> uploadStoryVideo(File file) async {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'story-video');
  }

  Future<String> uploadChatVideo(File file, String chatId) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'chat-video', subPath: chatId);
  }

  Future<String> uploadChatFile(File file, String chatId) {
    return _uploadViaBackend(bucket: 'posts', file: file, kind: 'chat-file', subPath: chatId);
  }

  Future<void> deleteAllMyMedia() async {
    try {
      await ApiClient.instance.post('/storage/delete-user-media');
      debugPrint('[StorageService] deleteAllMyMedia OK');
    } catch (e) {
      debugPrint('[StorageService] deleteAllMyMedia failed: $e');
      throw StorageException('Failed to delete media: $e');
    }
  }

  Future<String> _uploadViaBackend({
    required String bucket,
    required File file,
    required String kind,
    String? subPath,
  }) async {
    final exists = await file.exists();
    if (!exists) throw StorageException('File not found at ${file.path}');
    final size = await file.length();
    if (size == 0) throw StorageException('File is empty: ${file.path}');

    final ext = _extensionOf(file.path);
    final contentType = _contentTypeOf(ext);

    try {
      // 1. Request upload URL from Hono backend
      final data = await ApiClient.instance.post(
        '/storage/upload-url',
        body: {
          'bucket': bucket,
          'kind': kind,
          'ext': ext,
          if (subPath != null) 'subPath': subPath,
        },
      );

      final uploadUrl = data['uploadUrl'] as String;
      final publicUrl = data['publicUrl'] as String;

      // 2. Read bytes and PUT to uploadUrl
      final bytes = await file.readAsBytes();
      final headers = <String, String>{
        'Content-Type': contentType,
      };

      if (ApiClient.instance.accessToken != null) {
        headers['Authorization'] = 'Bearer ${ApiClient.instance.accessToken}';
      }

      final uploadRes = await http.put(
        Uri.parse(uploadUrl),
        headers: headers,
        body: bytes,
      ).timeout(const Duration(seconds: 60));

      if (uploadRes.statusCode < 200 || uploadRes.statusCode >= 300) {
        throw StorageException('Media upload failed (${uploadRes.statusCode}): ${uploadRes.body}');
      }

      return publicUrl;
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Upload failed: $e');
    }
  }

  String _extensionOf(String p) {
    final i = p.lastIndexOf('.');
    return i >= 0 && i < p.length - 1 ? p.substring(i + 1).toLowerCase() : '';
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
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
