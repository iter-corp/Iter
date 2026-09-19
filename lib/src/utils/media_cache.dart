import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// App-wide media disk cache for feed/travel/discuss content.
///
/// Two concerns are handled here:
///
///  * **Images** — a [CacheManager] with a large capacity so post
///    images stay on disk and don't re-download every time a tab is
///    reopened. Wire it into `CachedNetworkImage(cacheManager: ...)`.
///
///  * **Videos** — [videoFile] downloads a post video once and returns
///    the cached local [File]; playing from a file (instead of
///    streaming the network URL) means it never hits the server again.
///
/// The cache is generous on purpose ("can cache large size"): up to
/// [_maxCacheObjects] files kept for [_staleAfter], which comfortably
/// covers a heavy scrolling session across all three tabs.
class MediaCache {
  MediaCache._();

  // ── Tuning ────────────────────────────────────────────────────
  // Large limits so a lot of media survives between sessions.
  static const int _maxCacheObjects = 800;
  static const Duration _staleAfter = Duration(days: 30);

  /// Cache manager for post **images**. Shared by every
  /// `CachedNetworkImage` that renders feed/travel/discuss content.
  static final CacheManager images = CacheManager(
    Config(
      'itrPostImageCache',
      stalePeriod: _staleAfter,
      maxNrOfCacheObjects: _maxCacheObjects,
    ),
  );

  /// Cache manager for post **videos**. Kept separate from images so
  /// large video files don't evict images (and vice versa).
  static final CacheManager videos = CacheManager(
    Config(
      'itrPostVideoCache',
      stalePeriod: _staleAfter,
      maxNrOfCacheObjects: _maxCacheObjects,
    ),
  );

  /// Returns the post video at [url] as a cached local file. Downloads
  /// it on first use, then serves the on-disk copy on every later
  /// call — so the same video never streams from the server twice.
  static Future<File> videoFile(String url) async {
    final info = await videos.getSingleFile(url);
    return info;
  }

  /// Clears all cached post media. Useful for a "clear cache" setting.
  static Future<void> clear() async {
    await images.emptyCache();
    await videos.emptyCache();
  }
}

/// Normalizes any legacy or relative media URL to a clean, absolute HTTPS URL.
String normalizeMediaUrl(String? raw) {
  if (raw == null) return '';
  var url = raw.trim();
  if (url.isEmpty) return '';

  // 1. Rewrite legacy Supabase storage URLs
  if (url.startsWith('https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public')) {
    url = url.replaceFirst(
      'https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public',
      'https://iterglobal.icu/uploads',
    );
  }

  // 2. Rewrite legacy local IP URLs
  if (url.contains(':3000/uploads/')) {
    url = url.replaceFirst(RegExp(r'https?:\/\/[^\/]+:3000\/uploads\/'), 'https://iterglobal.icu/uploads/');
  }

  // 3. Resolve relative /uploads/... paths
  if (url.startsWith('/uploads/')) {
    url = 'https://iterglobal.icu$url';
  }

  // 4. Upgrade HTTP to HTTPS for domain
  if (url.startsWith('http://iterglobal.icu')) {
    url = url.replaceFirst('http://', 'https://');
  }

  return url;
}
