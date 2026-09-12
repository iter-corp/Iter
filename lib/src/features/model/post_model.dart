import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String? authorAvatar;
  final String caption;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final int likesCount;
  final int commentsCount;
  final bool isPrivate;
  final DateTime? createdAt;
  final String? postPlaceName;
  final String? postPlaceCity;
  final double? postLat;
  final double? postLng;
  final bool postLocationExact;
  final double? travelDistanceKm;
  final String? travelDistanceLabel;

  /// Set on a feed/travel post once it has been turned into a Discuss
  /// topic — holds the id of that QA document. Null when the post has
  /// no Discuss thread yet.
  final String? discussTopicId;

  /// Set on a Discuss (QA) post that was created *from* a feed/travel
  /// post — holds the id of that original post.
  final String? sourcePostId;
  final String? discussKind;

  Post({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    required this.authorAvatar,
    required this.caption,
    required this.imageUrls,
    this.videoUrls = const [],
    required this.likesCount,
    required this.commentsCount,
    required this.isPrivate,
    required this.createdAt,
    this.postPlaceName,
    this.postPlaceCity,
    this.postLat,
    this.postLng,
    this.postLocationExact = false,
    this.travelDistanceKm,
    this.travelDistanceLabel,
    this.discussTopicId,
    this.sourcePostId,
    this.discussKind,
  });

  static String? _sanitizeMediaUrl(String? url) {
    if (url == null) return null;
    const legacyPrefix = 'https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public';
    if (url.startsWith(legacyPrefix)) {
      return url.replaceFirst(legacyPrefix, 'https://iterglobal.icu/uploads');
    }
    return url;
  }

  static List<String> _sanitizeMediaUrls(List? list) {
    if (list == null) return const [];
    return list
        .whereType<String>()
        .map((u) => _sanitizeMediaUrl(u) ?? u)
        .where((u) => u.isNotEmpty)
        .toList();
  }

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    final postLocation = data['postLocation'];
    final postLocationMap = postLocation is Map ? postLocation : null;
    return Post(
      id: d.id,
      authorUid: data['authorUid'] as String? ?? '',
      authorUsername: data['authorUsername'] as String? ?? 'unknown',
      authorAvatar: _sanitizeMediaUrl(data['authorAvatar'] as String?),
      caption: data['caption'] as String? ?? '',
      imageUrls: _sanitizeMediaUrls(data['imageUrls'] as List?),
      videoUrls: _sanitizeMediaUrls(data['videoUrls'] as List?),
      likesCount: (data['likesCount'] as int?) ?? 0,
      commentsCount: (data['commentsCount'] as int?) ?? 0,
      isPrivate: (data['isPrivate'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      postPlaceName: (data['postPlaceName'] as String?)?.trim(),
      postPlaceCity: (data['postPlaceCity'] as String?)?.trim(),
      postLat: (postLocationMap?['lat'] as num?)?.toDouble(),
      postLng: (postLocationMap?['lng'] as num?)?.toDouble(),
      postLocationExact: (data['postLocationExact'] as bool?) ?? false,
      discussTopicId: (data['discussTopicId'] as String?)?.trim(),
      sourcePostId: (data['sourcePostId'] as String?)?.trim(),
      discussKind: (data['discussKind'] as String?)?.trim(),
    );
  }

  factory Post.fromJson(Map<String, dynamic> data) {
    final postLocation = data['postLocation'];
    final postLocationMap = postLocation is Map ? postLocation : null;

    DateTime? createdAt;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    } else if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw);
    } else if (createdRaw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw);
    }

    return Post(
      id: (data['id'] ?? data['postId']) as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorUsername: data['authorUsername'] as String? ?? 'unknown',
      authorAvatar: _sanitizeMediaUrl(data['authorAvatar'] as String?),
      caption: data['caption'] as String? ?? '',
      imageUrls: _sanitizeMediaUrls(data['imageUrls'] as List?),
      videoUrls: _sanitizeMediaUrls(data['videoUrls'] as List?),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      isPrivate: (data['isPrivate'] as bool?) ?? false,
      createdAt: createdAt,
      postPlaceName: (data['postPlaceName'] as String?)?.trim(),
      postPlaceCity: (data['postPlaceCity'] as String?)?.trim(),
      postLat: (postLocationMap?['lat'] as num?)?.toDouble() ?? (data['postLat'] as num?)?.toDouble(),
      postLng: (postLocationMap?['lng'] as num?)?.toDouble() ?? (data['postLng'] as num?)?.toDouble(),
      postLocationExact: (data['postLocationExact'] as bool?) ?? false,
      discussTopicId: (data['discussTopicId'] as String?)?.trim(),
      sourcePostId: (data['sourcePostId'] as String?)?.trim(),
      discussKind: (data['discussKind'] as String?)?.trim(),
      travelDistanceKm: (data['travelDistanceKm'] ?? data['distanceKm'] as num?)?.toDouble(),
      travelDistanceLabel: (data['travelDistanceLabel'] ?? data['distanceLabel'] as String?)?.trim(),
    );
  }

  factory Post.fromTravelMap(Map<String, dynamic> data) {
    final postLocation = data['postLocation'];
    final postLocationMap = postLocation is Map ? postLocation : null;

    DateTime? createdAt;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    } else if (createdRaw is Map && createdRaw['_seconds'] is num) {
      final seconds = (createdRaw['_seconds'] as num).toInt();
      final nanos = (createdRaw['_nanoseconds'] as num?)?.toInt() ?? 0;
      createdAt = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000 + (nanos / 1000000).round(),
      );
    }

    return Post(
      id: data['postId'] as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorUsername: data['authorUsername'] as String? ?? 'unknown',
      authorAvatar: data['authorAvatar'] as String?,
      caption: data['caption'] as String? ?? '',
      imageUrls: (data['imageUrls'] as List?)?.cast<String>() ?? const [],
      videoUrls: (data['videoUrls'] as List?)?.cast<String>() ?? const [],
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      isPrivate: (data['isPrivate'] as bool?) ?? false,
      createdAt: createdAt,
      postPlaceName: (data['postPlaceName'] as String?)?.trim(),
      postPlaceCity: (data['postPlaceCity'] as String?)?.trim(),
      postLat: (postLocationMap?['lat'] as num?)?.toDouble(),
      postLng: (postLocationMap?['lng'] as num?)?.toDouble(),
      postLocationExact: (data['postLocationExact'] as bool?) ?? false,
      travelDistanceKm: (data['distanceKm'] as num?)?.toDouble(),
      travelDistanceLabel: (data['distanceLabel'] as String?)?.trim(),
      discussKind: (data['discussKind'] as String?)?.trim(),
    );
  }
}
