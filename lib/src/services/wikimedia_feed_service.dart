import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/model/post_model.dart';

class WikimediaFeedService {
  static const String _baseEndpoint =
      'https://en.wikipedia.org/api/rest_v1/feed/featured';
  static const String _defaultAvatar =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/Wikipedia-logo-v2.svg/330px-Wikipedia-logo-v2.svg.png';

  final http.Client _client;

  // In-memory cache for offline resilience and fast loads
  List<Post> _cachedPosts = const [];

  WikimediaFeedService({http.Client? client})
      : _client = client ?? http.Client();

  /// Fetches daily featured articles, "On this day in history", "Did you know?",
  /// and trending informational topics from the Wikimedia REST API.
  Future<List<Post>> fetchFeed({DateTime? date}) async {
    final targetDate = date ?? DateTime.now().toUtc();
    final yyyy = targetDate.year.toString().padLeft(4, '0');
    final mm = targetDate.month.toString().padLeft(2, '0');
    final dd = targetDate.day.toString().padLeft(2, '0');

    final uri = Uri.parse('$_baseEndpoint/$yyyy/$mm/$dd');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'IterApp/1.0 (knowledge-feed@iterapp.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final posts = parseFeedJson(decoded, date: targetDate);
          if (posts.isNotEmpty) {
            _cachedPosts = posts;
            return posts;
          }
        }
      } else {
        debugPrint(
          '[WikimediaFeedService] Failed with HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e, st) {
      debugPrint('[WikimediaFeedService] Error fetching feed: $e\n$st');
    }

    return _cachedPosts;
  }

  /// Parses the raw Wikimedia Feed JSON payload into a list of [Post] objects.
  List<Post> parseFeedJson(Map<String, dynamic> json, {DateTime? date}) {
    final now = date ?? DateTime.now().toUtc();
    final posts = <Post>[];

    // 1. Today's Featured Article (tfa)
    final tfa = json['tfa'];
    if (tfa is Map<String, dynamic>) {
      final title = (tfa['titles']?['normalized'] as String?) ??
          (tfa['title'] as String?)?.replaceAll('_', ' ') ??
          '';
      final extract = (tfa['extract'] as String?)?.trim() ?? '';
      final description = (tfa['description'] as String?)?.trim();
      final imageUrl = _extractImageUrl(tfa);

      if (title.isNotEmpty && extract.isNotEmpty) {
        final caption = [
          title,
          if (description != null && description.isNotEmpty) '• $description',
          '',
          extract,
        ].join('\n').trim();

        posts.add(
          Post(
            id: 'wiki_tfa_${now.year}_${now.month}_${now.day}_${title.hashCode.abs()}',
            authorUid: 'wikimedia_foundation',
            authorUsername: 'Wikipedia • Featured Article',
            authorAvatar: _defaultAvatar,
            caption: caption,
            imageUrls: imageUrl != null ? [imageUrl] : const [],
            videoUrls: const [],
            likesCount: 0,
            commentsCount: 0,
            isPrivate: false,
            createdAt: now,
            discussKind: imageUrl == null ? 'discussion' : null,
            postPlaceName: 'Featured Article • Wikipedia',
            postPlaceCity: 'Daily Knowledge',
          ),
        );
      }
    }

    // 2. On this day in history (onthisday)
    final onThisDay = json['onthisday'];
    if (onThisDay is List) {
      for (var i = 0; i < onThisDay.length && i < 8; i++) {
        final item = onThisDay[i];
        if (item is! Map<String, dynamic>) continue;

        final year = item['year'];
        final text = (item['text'] as String?)?.trim() ?? '';
        final pages = item['pages'];
        String? imageUrl;
        if (pages is List && pages.isNotEmpty) {
          final firstPage = pages.first;
          if (firstPage is Map<String, dynamic>) {
            imageUrl = _extractImageUrl(firstPage);
          }
        }

        if (text.isNotEmpty) {
          final titleLine = year != null
              ? 'On This Day in $year'
              : 'On This Day in History';
          final caption = '$titleLine\n\n$text';

          posts.add(
            Post(
              id: 'wiki_otd_${now.year}_${now.month}_${now.day}_${i}_${text.hashCode.abs()}',
              authorUid: 'wikimedia_foundation',
              authorUsername: 'Wikipedia • History',
              authorAvatar: _defaultAvatar,
              caption: caption,
              imageUrls: imageUrl != null ? [imageUrl] : const [],
              videoUrls: const [],
              likesCount: 0,
              commentsCount: 0,
              isPrivate: false,
              createdAt: now.subtract(Duration(minutes: (i + 1) * 15)),
              discussKind: imageUrl == null ? 'discussion' : null,
              postPlaceName: 'History • Wikipedia',
              postPlaceCity: year != null ? 'Year $year' : 'History',
            ),
          );
        }
      }
    }

    // 3. Did You Know? trivia (dyk)
    final dyk = json['dyk'];
    if (dyk is List) {
      for (var i = 0; i < dyk.length && i < 6; i++) {
        final item = dyk[i];
        if (item is! Map<String, dynamic>) continue;

        final rawText = (item['text'] as String?)?.trim() ?? '';
        final cleanText = _stripHtml(rawText);
        final pages = item['pages'];
        String? imageUrl;
        if (pages is List && pages.isNotEmpty) {
          final firstPage = pages.first;
          if (firstPage is Map<String, dynamic>) {
            imageUrl = _extractImageUrl(firstPage);
          }
        }

        if (cleanText.isNotEmpty) {
          final caption = 'Did You Know?\n\n$cleanText';

          posts.add(
            Post(
              id: 'wiki_dyk_${now.year}_${now.month}_${now.day}_${i}_${cleanText.hashCode.abs()}',
              authorUid: 'wikimedia_foundation',
              authorUsername: 'Wikipedia • Trivia',
              authorAvatar: _defaultAvatar,
              caption: caption,
              imageUrls: imageUrl != null ? [imageUrl] : const [],
              videoUrls: const [],
              likesCount: 0,
              commentsCount: 0,
              isPrivate: false,
              createdAt: now.subtract(Duration(minutes: (i + 1) * 30)),
              discussKind: imageUrl == null ? 'discussion' : null,
              postPlaceName: 'Did You Know? • Trivia',
              postPlaceCity: 'Daily Curiosities',
            ),
          );
        }
      }
    }

    // 4. Trending Informational Topics (mostread)
    final mostread = json['mostread'];
    if (mostread is Map<String, dynamic>) {
      final articles = mostread['articles'];
      if (articles is List) {
        for (var i = 0; i < articles.length && i < 6; i++) {
          final article = articles[i];
          if (article is! Map<String, dynamic>) continue;

          final title = (article['titles']?['normalized'] as String?) ??
              (article['title'] as String?)?.replaceAll('_', ' ') ??
              '';
          final extract = (article['extract'] as String?)?.trim() ?? '';
          final views = article['views'];
          final imageUrl = _extractImageUrl(article);

          // Skip special pages like Main_Page or Search
          if (title.isEmpty ||
              title.toLowerCase() == 'main page' ||
              title.toLowerCase().startsWith('special:')) {
            continue;
          }

          if (extract.isNotEmpty) {
            final viewsLabel = views != null ? 'Trending • $views views today\n\n' : '';
            final caption = '$title\n\n$viewsLabel$extract';

            posts.add(
              Post(
                id: 'wiki_trend_${now.year}_${now.month}_${now.day}_${i}_${title.hashCode.abs()}',
                authorUid: 'wikimedia_foundation',
                authorUsername: 'Wikipedia • Trending',
                authorAvatar: _defaultAvatar,
                caption: caption,
                imageUrls: imageUrl != null ? [imageUrl] : const [],
                videoUrls: const [],
                likesCount: 0,
                commentsCount: 0,
                isPrivate: false,
                createdAt: now.subtract(Duration(minutes: (i + 1) * 45)),
                discussKind: imageUrl == null ? 'discussion' : null,
                postPlaceName: 'Trending Topic • Wikipedia',
                postPlaceCity: 'Popular Today',
              ),
            );
          }
        }
      }
    }

    return posts;
  }

  String? _extractImageUrl(Map<String, dynamic> data) {
    final original = data['originalimage']?['source'] as String?;
    if (original != null && original.startsWith('http')) return original;

    final thumbnail = data['thumbnail']?['source'] as String?;
    if (thumbnail != null && thumbnail.startsWith('http')) return thumbnail;

    return null;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
