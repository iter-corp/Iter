import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../features/model/post_model.dart';

class NasaApodService {
  static const String _defaultEndpoint =
      'https://api.nasa.gov/planetary/apod';
  static const String _defaultAvatar =
      'https://api.nasa.gov/assets/img/favicons/favicon-192.png';

  final http.Client _client;

  // In-memory cache to prevent blank screens on rate limits or offline mode
  List<Post> _cachedPosts = const [];

  NasaApodService({http.Client? client}) : _client = client ?? http.Client();

  String get _apiKey {
    if (dotenv.isInitialized) {
      final key = dotenv.env['NASA_API_KEY']?.trim();
      if (key != null && key.isNotEmpty) return key;
    }
    return 'DEMO_KEY';
  }

  /// Fetches astronomy pictures from the NASA APOD API and maps them
  /// into the app's [Post] model.
  Future<List<Post>> fetchApodPosts({int count = 10}) async {
    final uri = Uri.parse(_defaultEndpoint).replace(
      queryParameters: {
        'api_key': _apiKey,
        'count': count.toString(),
        'thumbs': 'true',
      },
    );

    try {
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 12),
          );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> items;
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map<String, dynamic>) {
          items = [decoded];
        } else {
          items = const [];
        }

        final posts = <Post>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          if (item is! Map<String, dynamic>) continue;
          final post = _mapApodToPost(item, index: i);
          if (post != null) {
            posts.add(post);
          }
        }

        if (posts.isNotEmpty) {
          _cachedPosts = posts;
          return posts;
        }
      } else {
        debugPrint(
          '[NasaApodService] API error status: ${response.statusCode}, body: ${response.body}',
        );
        // If count parameter failed (e.g. rate limits or server error), try single today's APOD as fallback
        if (_cachedPosts.isEmpty) {
          final singlePost = await _fetchSingleTodayApod();
          if (singlePost != null) {
            _cachedPosts = [singlePost];
            return _cachedPosts;
          }
        }
      }
    } catch (e, st) {
      debugPrint('[NasaApodService] Failed to fetch NASA APOD: $e\n$st');
    }

    // Return cached posts if network call failed or empty
    return _cachedPosts;
  }

  Future<Post?> _fetchSingleTodayApod() async {
    try {
      final uri = Uri.parse(_defaultEndpoint).replace(
        queryParameters: {
          'api_key': _apiKey,
          'thumbs': 'true',
        },
      );
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return _mapApodToPost(decoded, index: 0);
        }
      }
    } catch (_) {}
    return null;
  }

  Post? _mapApodToPost(Map<String, dynamic> data, {required int index}) {
    final title = (data['title'] as String?)?.trim() ?? '';
    final date = (data['date'] as String?)?.trim() ?? '';
    final explanation = (data['explanation'] as String?)?.trim() ?? '';
    final mediaType = (data['media_type'] as String?)?.trim().toLowerCase() ?? 'image';
    final copyright = (data['copyright'] as String?)?.replaceAll('\n', ' ').trim();

    // Prefer high-definition URL if present, fallback to standard url
    final hdUrl = (data['hdurl'] as String?)?.trim();
    final stdUrl = (data['url'] as String?)?.trim();
    final thumbUrl = (data['thumbnail_url'] as String?)?.trim();

    final List<String> imageUrls;
    final List<String> videoUrls;

    if (mediaType == 'image') {
      final img = (hdUrl != null && hdUrl.isNotEmpty) ? hdUrl : (stdUrl ?? '');
      if (img.isEmpty) return null;
      imageUrls = [img];
      videoUrls = const [];
    } else if (mediaType == 'video') {
      if (stdUrl == null || stdUrl.isEmpty) return null;
      // If video thumbnail exists, we can show image + video
      imageUrls = (thumbUrl != null && thumbUrl.isNotEmpty) ? [thumbUrl] : const [];
      videoUrls = [stdUrl];
    } else {
      final img = stdUrl ?? '';
      if (img.isEmpty) return null;
      imageUrls = [img];
      videoUrls = const [];
    }

    final caption = _buildCaption(
      title: title,
      date: date,
      copyright: copyright,
      explanation: explanation,
    );

    DateTime? createdAt;
    if (date.isNotEmpty) {
      createdAt = DateTime.tryParse(date);
    }
    createdAt ??= DateTime.now().subtract(Duration(hours: index * 6));

    final cleanId = date.isNotEmpty
        ? 'nasa_${date.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_$index'
        : 'nasa_${DateTime.now().millisecondsSinceEpoch}_$index';

    return Post(
      id: cleanId,
      authorUid: 'nasa_apod',
      authorUsername: 'NASA APOD',
      authorAvatar: _defaultAvatar,
      caption: caption,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      likesCount: 0,
      commentsCount: 0,
      isPrivate: false,
      createdAt: createdAt,
      discussKind: imageUrls.isEmpty ? 'discussion' : null,
      postPlaceName: 'Astronomy Picture of the Day',
      postPlaceCity: 'NASA',
    );
  }

  String _buildCaption({
    required String title,
    required String date,
    String? copyright,
    required String explanation,
  }) {
    final buffer = StringBuffer();
    if (title.isNotEmpty) {
      buffer.writeln(title);
    }
    if (date.isNotEmpty) {
      buffer.writeln('Date: $date');
    }
    if (copyright != null && copyright.isNotEmpty) {
      buffer.writeln('Credit: $copyright');
    }
    if (explanation.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(explanation);
    }
    return buffer.toString().trim();
  }
}
