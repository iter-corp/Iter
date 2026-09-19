import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'notification_service.dart';
import 'post_service.dart';
import 'sticker_service.dart';
import 'storage_service.dart';

class AdminConfig {
  final bool storiesEnabled;
  final bool repostsEnabled;
  final bool translateEnabled;
  final bool wikipediaEnabled;
  final String announcement;
  final bool maintenanceMode;
  final String minAppVersion;
  final String contactEmail;

  /// Public store links used by the in-app "Invite friends" share sheet.
  /// The app picks the right one for the running platform (iOS → App Store,
  /// Android → Google Play). Empty values fall back to the other store link
  /// or a generic message.
  final String iosAppStoreUrl;
  final String androidPlayStoreUrl;

  /// Event-type options admins choose from when creating an event and users
  /// filter notifications by. Editable from the admin dashboard; falls back to
  /// [kEventTypes] when unset/empty.
  final List<String> eventTypes;

  /// Country options used for event tagging/filtering. This list is static
  /// (all countries + Online) and is not editable from the admin dashboard.
  final List<String> eventCountries;

  /// Profile personalization options shown in onboarding/edit profile.
  /// Editable from admin settings; each list falls back to canonical defaults
  /// when unset/empty.
  final List<String> profileProfessionOptions;
  final List<String> profileFieldOptions;
  final List<String> profileAcademicLevelOptions;
  final List<String> profileGoalOptions;

  /// English profanity words used by chat moderation.
  final bool welcomeMessageEnabled;
  final String welcomeMessage;
  final List<String> profanityWordsEn;

  const AdminConfig({
    this.storiesEnabled = true,
    this.repostsEnabled = true,
    this.translateEnabled = true,
    this.wikipediaEnabled = true,
    this.announcement = '',
    this.welcomeMessageEnabled = true,
    this.welcomeMessage = '',
    this.maintenanceMode = false,
    this.minAppVersion = '1.0.0',
    this.contactEmail = '',
    this.iosAppStoreUrl = '',
    this.androidPlayStoreUrl = '',
    this.eventTypes = kEventTypes,
    this.eventCountries = kEventCountries,
    this.profileProfessionOptions = kProfileProfessionOptions,
    this.profileFieldOptions = kProfileFieldOptions,
    this.profileAcademicLevelOptions = kProfileAcademicLevelOptions,
    this.profileGoalOptions = kProfileGoalOptions,
    this.profanityWordsEn = kProfanityWordsEn,
  });

  factory AdminConfig.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const {};
    List<String> cleanList(dynamic raw, List<String> fallback) {
      if (raw is! List) return fallback;
      final out = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return out.isEmpty ? fallback : out;
    }

    final meta = (m['metadata'] as Map<String, dynamic>?) ?? const {};
    final rawWelcome = (meta['welcomeMessage'] as String?) ??
        (m['welcomeMessage'] as String?);
    final rawWelcomeEnabled = (meta['welcomeMessageEnabled'] as bool?) ??
        (m['welcomeMessageEnabled'] as bool?);
    final rawWikipediaEnabled = (meta['wikipediaEnabled'] as bool?) ??
        (m['wikipediaEnabled'] as bool?);
    final rawAnnouncement = (m['announcement'] as String?) ?? '';

    final effectiveWelcome = (rawWelcome != null && rawWelcome.trim().isNotEmpty)
        ? rawWelcome
        : (rawAnnouncement.toLowerCase().contains('welcome')
            ? rawAnnouncement
            : 'Welcome to Iter! Connect, explore, and share with your community.');

    return AdminConfig(
      storiesEnabled: (m['storiesEnabled'] as bool?) ?? true,
      repostsEnabled: (m['repostsEnabled'] as bool?) ?? true,
      translateEnabled: (m['translateEnabled'] as bool?) ?? true,
      wikipediaEnabled: rawWikipediaEnabled ?? true,
      announcement: rawAnnouncement,
      welcomeMessageEnabled: rawWelcomeEnabled ?? true,
      welcomeMessage: effectiveWelcome,
      maintenanceMode: (m['maintenanceMode'] as bool?) ?? false,
      minAppVersion: (m['minAppVersion'] as String?) ?? '1.0.0',
      contactEmail: (m['contactEmail'] as String?) ?? '',
      iosAppStoreUrl: (m['iosAppStoreUrl'] as String?) ?? '',
      androidPlayStoreUrl: (m['androidPlayStoreUrl'] as String?) ?? '',
      eventTypes: cleanList(m['eventTypes'], kEventTypes),
      eventCountries: kEventCountries,
      profileProfessionOptions:
          cleanList(m['profileProfessionOptions'], kProfileProfessionOptions),
      profileFieldOptions:
          cleanList(m['profileFieldOptions'], kProfileFieldOptions),
      profileAcademicLevelOptions: cleanList(
          m['profileAcademicLevelOptions'], kProfileAcademicLevelOptions),
      profileGoalOptions:
          cleanList(m['profileGoalOptions'], kProfileGoalOptions),
      profanityWordsEn: cleanList(m['profanityWordsEn'], kProfanityWordsEn),
    );
  }

  Map<String, dynamic> toMap() => {
        'storiesEnabled': storiesEnabled,
        'repostsEnabled': repostsEnabled,
        'translateEnabled': translateEnabled,
        'wikipediaEnabled': wikipediaEnabled,
        'announcement': announcement,
        'welcomeMessageEnabled': welcomeMessageEnabled,
        'welcomeMessage': welcomeMessage,
        'metadata': {
          'welcomeMessageEnabled': welcomeMessageEnabled,
          'welcomeMessage': welcomeMessage,
          'wikipediaEnabled': wikipediaEnabled,
        },
        'maintenanceMode': maintenanceMode,
        'minAppVersion': minAppVersion,
        'contactEmail': contactEmail,
        'iosAppStoreUrl': iosAppStoreUrl,
        'androidPlayStoreUrl': androidPlayStoreUrl,
        'eventTypes': eventTypes,
        'profileProfessionOptions': profileProfessionOptions,
        'profileFieldOptions': profileFieldOptions,
        'profileAcademicLevelOptions': profileAcademicLevelOptions,
        'profileGoalOptions': profileGoalOptions,
        'profanityWordsEn': profanityWordsEn,
      };

  AdminConfig copyWith({
    bool? storiesEnabled,
    bool? repostsEnabled,
    bool? translateEnabled,
    bool? wikipediaEnabled,
    String? announcement,
    bool? welcomeMessageEnabled,
    String? welcomeMessage,
    bool? maintenanceMode,
    String? minAppVersion,
    String? contactEmail,
    String? iosAppStoreUrl,
    String? androidPlayStoreUrl,
    List<String>? eventTypes,
    List<String>? eventCountries,
    List<String>? profileProfessionOptions,
    List<String>? profileFieldOptions,
    List<String>? profileAcademicLevelOptions,
    List<String>? profileGoalOptions,
    List<String>? profanityWordsEn,
  }) {
    return AdminConfig(
      storiesEnabled: storiesEnabled ?? this.storiesEnabled,
      repostsEnabled: repostsEnabled ?? this.repostsEnabled,
      translateEnabled: translateEnabled ?? this.translateEnabled,
      wikipediaEnabled: wikipediaEnabled ?? this.wikipediaEnabled,
      announcement: announcement ?? this.announcement,
      welcomeMessageEnabled:
          welcomeMessageEnabled ?? this.welcomeMessageEnabled,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      contactEmail: contactEmail ?? this.contactEmail,
      iosAppStoreUrl: iosAppStoreUrl ?? this.iosAppStoreUrl,
      androidPlayStoreUrl: androidPlayStoreUrl ?? this.androidPlayStoreUrl,
      eventTypes: eventTypes ?? this.eventTypes,
      eventCountries: eventCountries ?? this.eventCountries,
      profileProfessionOptions:
          profileProfessionOptions ?? this.profileProfessionOptions,
      profileFieldOptions: profileFieldOptions ?? this.profileFieldOptions,
      profileAcademicLevelOptions:
          profileAcademicLevelOptions ?? this.profileAcademicLevelOptions,
      profileGoalOptions: profileGoalOptions ?? this.profileGoalOptions,
      profanityWordsEn: profanityWordsEn ?? this.profanityWordsEn,
    );
  }
}

/// Canonical personalization options shown in onboarding/edit-profile. Admins
/// can override these lists from App settings.
const List<String> kProfileProfessionOptions = [
  'Student',
  'Researcher',
  'Professor',
  'Traveler',
];

const List<String> kProfileFieldOptions = [
  'Tech',
  'Medicine',
  'Law',
  'Business',
  'Arts',
  'Engineering',
  'Science',
  'Education',
  'Social sciences',
  'Other',
];

const List<String> kProfileAcademicLevelOptions = [
  'Undergraduate',
  'Masters',
  'PhD',
  'Faculty',
];

const List<String> kProfileGoalOptions = [
  'Internships',
  'Scholarships',
  'Conferences',
  'Research',
  'Networking',
  'Local events',
];

const List<String> kProfanityWordsEn = [
  'arse',
  'asshole',
  'bastard',
  'bitch',
  'bloody',
  'bollocks',
  'bullshit',
  'crap',
  'damn',
  'dick',
  'freaking',
  'fuck',
  'fucker',
  'fucking',
  'goddamn',
  'hell',
  'motherfucker',
  'piss',
  'prick',
  'shit',
  'slut',
  'whore',
  'wanker',
];

/// Canonical event-type options. Admins pick one when creating an event;
/// users can filter event notifications by these.
const List<String> kEventTypes = [
  'Scholarship',
  'Internship',
  'Research',
  'Conference',
  'Summer Program',
  'Competition',
  'Leadership',
  'Youth Summit',
  'other',
];

/// Canonical static country options used for event tagging/filtering.
/// Kept comprehensive (all countries + Online) so admins do not need to
/// maintain this list from settings. Stored lower-cased on event docs as
/// `locationCountry`.
const List<String> kEventCountries = [
  'Afghanistan',
  'Aland Islands',
  'Albania',
  'Algeria',
  'American Samoa',
  'Andorra',
  'Angola',
  'Anguilla',
  'Antarctica',
  'Antigua And Barbuda',
  'Argentina',
  'Armenia',
  'Aruba',
  'Australia',
  'Austria',
  'Azerbaijan',
  'Bahamas The',
  'Bahrain',
  'Bangladesh',
  'Barbados',
  'Belarus',
  'Belgium',
  'Belize',
  'Benin',
  'Bermuda',
  'Bhutan',
  'Bolivia',
  'Bonaire, Sint Eustatius and Saba',
  'Bosnia and Herzegovina',
  'Botswana',
  'Bouvet Island',
  'Brazil',
  'British Indian Ocean Territory',
  'Brunei',
  'Bulgaria',
  'Burkina Faso',
  'Burundi',
  'Cambodia',
  'Cameroon',
  'Canada',
  'Cape Verde',
  'Cayman Islands',
  'Central African Republic',
  'Chad',
  'Chile',
  'China',
  'Christmas Island',
  'Cocos (Keeling) Islands',
  'Colombia',
  'Comoros',
  'Congo',
  'Congo The Democratic Republic Of The',
  'Cook Islands',
  'Costa Rica',
  'Cote D\'Ivoire (Ivory Coast)',
  'Croatia (Hrvatska)',
  'Cuba',
  'Curaçao',
  'Cyprus',
  'Czech Republic',
  'Denmark',
  'Djibouti',
  'Dominica',
  'Dominican Republic',
  'East Timor',
  'Ecuador',
  'Egypt',
  'El Salvador',
  'Equatorial Guinea',
  'Eritrea',
  'Estonia',
  'Ethiopia',
  'Falkland Islands',
  'Faroe Islands',
  'Fiji Islands',
  'Finland',
  'France',
  'French Guiana',
  'French Polynesia',
  'French Southern Territories',
  'Gabon',
  'Gambia The',
  'Georgia',
  'Germany',
  'Ghana',
  'Gibraltar',
  'Greece',
  'Greenland',
  'Grenada',
  'Guadeloupe',
  'Guam',
  'Guatemala',
  'Guernsey and Alderney',
  'Guinea',
  'Guinea-Bissau',
  'Guyana',
  'Haiti',
  'Heard Island and McDonald Islands',
  'Honduras',
  'Hong Kong S.A.R.',
  'Hungary',
  'Iceland',
  'India',
  'Indonesia',
  'Iran',
  'Iraq',
  'Ireland',
  'Israel',
  'Italy',
  'Jamaica',
  'Japan',
  'Jersey',
  'Jordan',
  'Kazakhstan',
  'Kenya',
  'Kiribati',
  'Korea North',
  'Korea South',
  'Kosovo',
  'Kuwait',
  'Kyrgyzstan',
  'Laos',
  'Latvia',
  'Lebanon',
  'Lesotho',
  'Liberia',
  'Libya',
  'Liechtenstein',
  'Lithuania',
  'Luxembourg',
  'Macau S.A.R.',
  'Macedonia',
  'Madagascar',
  'Malawi',
  'Malaysia',
  'Maldives',
  'Mali',
  'Malta',
  'Man (Isle of)',
  'Marshall Islands',
  'Martinique',
  'Mauritania',
  'Mauritius',
  'Mayotte',
  'Mexico',
  'Micronesia',
  'Moldova',
  'Monaco',
  'Mongolia',
  'Montenegro',
  'Montserrat',
  'Morocco',
  'Mozambique',
  'Myanmar',
  'Namibia',
  'Nauru',
  'Nepal',
  'Netherlands The',
  'New Caledonia',
  'New Zealand',
  'Nicaragua',
  'Niger',
  'Nigeria',
  'Niue',
  'Norfolk Island',
  'Northern Mariana Islands',
  'Norway',
  'Oman',
  'Pakistan',
  'Palau',
  'Palestinian Territory Occupied',
  'Panama',
  'Papua new Guinea',
  'Paraguay',
  'Peru',
  'Philippines',
  'Pitcairn Island',
  'Poland',
  'Portugal',
  'Puerto Rico',
  'Qatar',
  'Reunion',
  'Romania',
  'Russia',
  'Rwanda',
  'Saint Helena',
  'Saint Kitts And Nevis',
  'Saint Lucia',
  'Saint Pierre and Miquelon',
  'Saint Vincent And The Grenadines',
  'Saint-Barthelemy',
  'Saint-Martin (French part)',
  'Samoa',
  'San Marino',
  'Sao Tome and Principe',
  'Saudi Arabia',
  'Senegal',
  'Serbia',
  'Seychelles',
  'Sierra Leone',
  'Singapore',
  'Sint Maarten (Dutch part)',
  'Slovakia',
  'Slovenia',
  'Solomon Islands',
  'Somalia',
  'South Africa',
  'South Georgia',
  'South Sudan',
  'Spain',
  'Sri Lanka',
  'Sudan',
  'Suriname',
  'Svalbard And Jan Mayen Islands',
  'Swaziland',
  'Sweden',
  'Switzerland',
  'Syria',
  'Taiwan',
  'Tajikistan',
  'Tanzania',
  'Thailand',
  'Togo',
  'Tokelau',
  'Tonga',
  'Trinidad And Tobago',
  'Tunisia',
  'Turkey',
  'Turkmenistan',
  'Turks And Caicos Islands',
  'Tuvalu',
  'Uganda',
  'Ukraine',
  'United Arab Emirates',
  'United Kingdom',
  'United States',
  'United States Minor Outlying Islands',
  'Uruguay',
  'Uzbekistan',
  'Vanuatu',
  'Vatican City State (Holy See)',
  'Venezuela',
  'Vietnam',
  'Virgin Islands (British)',
  'Virgin Islands (US)',
  'Wallis And Futuna Islands',
  'Western Sahara',
  'Yemen',
  'Zambia',
  'Zimbabwe',
  'Online',
];

/// Canonical funding-status options admins choose from when creating events.
const List<String> kEventFundingStatuses = [
  'Fully Funded',
  'Partially Funded',
  'Self Funded',
];

class AdminEvent {
  final String id;
  final String title;
  final String subtitle;
  final String location;
  final String description;
  final String link;
  final String phone;
  final String email;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final DateTime? deadlineAt;

  /// One of [kEventTypes]; empty when the admin didn't set one (legacy events).
  final String eventType;

  /// One of [kEventCountries]; empty when the admin didn't set one (legacy
  /// events). Stored on the doc lower-cased as `locationCountry` for matching.
  final String country;

  /// Funding status label chosen by admin (empty on legacy events).
  final String funds;

  /// Optional pin coordinates for the events map. Null when unknown.
  final double? lat;
  final double? lng;

  /// UID of the admin who created the event. Used to render the
  /// author profile chip on the event detail screen. Empty on
  /// legacy docs that pre-date the field.
  final String createdByUid;

  const AdminEvent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.description,
    required this.link,
    required this.phone,
    required this.email,
    required this.imageUrls,
    required this.createdAt,
    this.deadlineAt,
    this.eventType = '',
    this.country = '',
    this.funds = '',
    this.lat,
    this.lng,
    this.createdByUid = '',
  });

  factory AdminEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final loc = d['geo'];
    final geoMap = loc is Map ? loc : null;
    return AdminEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      subtitle: (d['subtitle'] as String?) ?? '',
      location: (d['location'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      link: (d['link'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? const [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      deadlineAt: (d['deadline'] as Timestamp?)?.toDate(),
      eventType: (d['eventType'] as String?) ?? '',
      // `country` keeps the admin's original casing for display/editing;
      // `locationCountry` (lower-cased) is the matching key.
      country: ((d['country'] as String?)?.trim().isNotEmpty ?? false)
          ? (d['country'] as String).trim()
          : ((d['locationCountry'] as String?) ?? '').trim(),
      funds: (d['funds'] as String?) ?? '',
      lat: (geoMap?['lat'] as num?)?.toDouble(),
      lng: (geoMap?['lng'] as num?)?.toDouble(),
      createdByUid: (d['createdByUid'] as String?) ?? '',
    );
  }

  factory AdminEvent.fromJson(Map<String, dynamic> d) {
    final geoMap = d['geo'] is Map ? d['geo'] as Map : null;
    final rawImages = d['imageUrls'] ?? d['image_urls'] ?? d['images'];
    final cover = d['coverImageUrl'] ?? d['cover_image_url'] ?? d['coverImage'] ?? d['cover_image'];
    final imgList = rawImages is List
        ? rawImages.map((e) => e.toString()).toList()
        : (cover != null && cover.toString().isNotEmpty ? [cover.toString()] : const <String>[]);
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return AdminEvent(
      id: d['id']?.toString() ?? '',
      title: d['title']?.toString() ?? '',
      subtitle: d['subtitle']?.toString() ?? d['location']?.toString() ?? '',
      location: d['location']?.toString() ?? '',
      description: d['description']?.toString() ?? '',
      link: d['linkUrl']?.toString() ?? d['link_url']?.toString() ?? d['link']?.toString() ?? '',
      phone: d['phone']?.toString() ?? '',
      email: d['email']?.toString() ?? '',
      imageUrls: imgList,
      createdAt: parseDate(d['createdAt'] ?? d['created_at']),
      deadlineAt: parseDate(d['deadline'] ?? d['startDate'] ?? d['start_date'] ?? d['endDate'] ?? d['end_date']),
      eventType: d['eventType']?.toString() ?? d['event_type']?.toString() ?? '',
      country: ((d['country']?.toString().trim().isNotEmpty ?? false))
          ? d['country'].toString().trim()
          : (d['locationCountry']?.toString() ?? d['location_country']?.toString() ?? '').trim(),
      funds: d['funds']?.toString() ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? (geoMap?['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble() ?? (geoMap?['lng'] as num?)?.toDouble(),
      createdByUid: d['authorUid']?.toString() ?? d['author_uid']?.toString() ?? d['createdByUid']?.toString() ?? d['created_by_uid']?.toString() ?? '',
    );
  }
}

class PostReport {
  final String id;
  final String postId;
  final String postAuthorUid;
  final String postAuthorUsername;
  final String? postAuthorAvatar;
  final String postCaption;
  final String reporterUid;
  final String reporterUsername;
  final String reason;
  final String? details;
  final bool resolved;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const PostReport({
    required this.id,
    required this.postId,
    required this.postAuthorUid,
    required this.postAuthorUsername,
    required this.postAuthorAvatar,
    required this.postCaption,
    required this.reporterUid,
    required this.reporterUsername,
    required this.reason,
    required this.details,
    required this.resolved,
    required this.createdAt,
    required this.resolvedAt,
  });

  factory PostReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PostReport(
      id: doc.id,
      postId: (d['postId'] as String?) ?? '',
      postAuthorUid: (d['postAuthorUid'] as String?) ?? '',
      postAuthorUsername: (d['postAuthorUsername'] as String?) ?? '',
      postAuthorAvatar: d['postAuthorAvatar'] as String?,
      postCaption: (d['postCaption'] as String?) ?? '',
      reporterUid: (d['reporterUid'] as String?) ?? '',
      reporterUsername: (d['reporterUsername'] as String?) ?? '',
      reason: (d['reason'] as String?) ?? '',
      details: d['details'] as String?,
      resolved: (d['resolved'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      resolvedAt: (d['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class UserProfileReport {
  final String id;
  final String targetUid;
  final String targetUsername;
  final String? targetAvatar;
  final String reporterUid;
  final String reporterUsername;
  final String reason;
  final String? details;
  final bool resolved;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const UserProfileReport({
    required this.id,
    required this.targetUid,
    required this.targetUsername,
    required this.targetAvatar,
    required this.reporterUid,
    required this.reporterUsername,
    required this.reason,
    required this.details,
    required this.resolved,
    required this.createdAt,
    required this.resolvedAt,
  });

  factory UserProfileReport.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return UserProfileReport(
      id: doc.id,
      targetUid: (d['targetUid'] as String?) ?? '',
      targetUsername: (d['targetUsername'] as String?) ?? '',
      targetAvatar: d['targetAvatar'] as String?,
      reporterUid: (d['reporterUid'] as String?) ?? '',
      reporterUsername: (d['reporterUsername'] as String?) ?? '',
      reason: (d['reason'] as String?) ?? '',
      details: d['details'] as String?,
      resolved: (d['resolved'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      resolvedAt: (d['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CommentReport {
  final String id;
  final String postId;
  final String commentId;
  final String commentText;
  final String commentAuthorUid;
  final String commentAuthorUsername;
  final String? commentAuthorAvatar;
  final String surface; // 'comment' | 'answer' | 'reply'
  final bool isReply;
  final String reporterUid;
  final String reporterUsername;
  final String reason;
  final String? details;
  final bool resolved;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const CommentReport({
    required this.id,
    required this.postId,
    required this.commentId,
    required this.commentText,
    required this.commentAuthorUid,
    required this.commentAuthorUsername,
    required this.commentAuthorAvatar,
    required this.surface,
    required this.isReply,
    required this.reporterUid,
    required this.reporterUsername,
    required this.reason,
    required this.details,
    required this.resolved,
    required this.createdAt,
    required this.resolvedAt,
  });

  factory CommentReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CommentReport(
      id: doc.id,
      postId: (d['postId'] as String?) ?? '',
      commentId: (d['commentId'] as String?) ?? '',
      commentText: (d['commentText'] as String?) ?? '',
      commentAuthorUid: (d['commentAuthorUid'] as String?) ?? '',
      commentAuthorUsername: (d['commentAuthorUsername'] as String?) ?? '',
      commentAuthorAvatar: d['commentAuthorAvatar'] as String?,
      surface: (d['surface'] as String?) ?? 'comment',
      isReply: (d['isReply'] as bool?) ?? false,
      reporterUid: (d['reporterUid'] as String?) ?? '',
      reporterUsername: (d['reporterUsername'] as String?) ?? '',
      reason: (d['reason'] as String?) ?? '',
      details: d['details'] as String?,
      resolved: (d['resolved'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      resolvedAt: (d['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notifications = NotificationService();

  Stream<AdminConfig> streamConfig() async* {
    try {
      final res = await ApiClient.instance.get('/dynamic/config');
      if (res is Map<String, dynamic>) {
        yield AdminConfig.fromMap(res);
      } else {
        yield const AdminConfig();
      }
    } catch (_) {
      yield const AdminConfig();
    }
  }

  Future<void> saveConfig(AdminConfig cfg) async {
    try {
      await ApiClient.instance.patch('/admin/config', body: cfg.toMap());
    } catch (e) {
      debugPrint('[AdminService] saveConfig error: $e');
    }
  }

  // -------- Users --------
  Stream<List<Map<String, dynamic>>> streamUsers({String query = ''}) {
    return _db.collection('users').snapshots().map((snap) {
      final q = query.trim().toLowerCase();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).where((u) {
        if (q.isEmpty) return true;
        final name = (u['username'] as String? ?? '').toLowerCase();
        final email = (u['email'] as String? ?? '').toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> suspendUser(String uid, bool suspended) =>
      _db.collection('users').doc(uid).update({'suspended': suspended});

  Future<void> setRole(String uid, String role) async {
    final userRef = _db.collection('users').doc(uid);
    final before = await userRef.get();
    final previousRole = (before.data()?['role'] as String?) ?? 'user';
    if (previousRole == role) return;

    await userRef.update({'role': role});

    String? title;
    String? subtitle;
    if (role == 'admin') {
      title = 'Admin access granted';
      subtitle = 'Iter Team made you an admin.';
    } else if (previousRole == 'admin' && role == 'user') {
      title = 'Admin access removed';
      subtitle = 'Iter Team removed your admin role.';
    } else if (role == 'org_admin') {
      title = 'Event manager access granted';
      subtitle = 'Iter Team approved you as an event manager.';
    } else if (previousRole == 'org_admin' && role == 'user') {
      title = 'Event manager access removed';
      subtitle = 'Iter Team revoked your event manager access.';
    }

    if (title != null) {
      await _notifications.createSystemNotification(
        targetUid: uid,
        type: 'role_update',
        title: title,
        subtitle: subtitle,
      );
    }
  }

  /// Cascade-deletes ALL user data and adds their email to the blacklist.
  /// Runs client-side — relies on Firestore rules that grant admin delete
  /// permission on all traversed paths.
  Future<void> deleteUser(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final email = (userSnap.data()?['email'] as String?) ?? '';

    final posts =
        await _db.collection('posts').where('authorUid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await _deleteSubcollection(post.reference, 'likes');
      await _deleteSubcollection(post.reference, 'comments');
      await _deleteSubcollection(post.reference, 'reposts');
      await post.reference.delete();
    }

    final stories = await _db
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final story in stories.docs) {
      await _deleteSubcollection(story.reference, 'viewers');
      await story.reference.delete();
    }

    // Comments authored by the deleted user are intentionally kept on other
    // people's posts so the conversation history stays intact. The comment
    // tile renders "deleted user" when the author doc no longer exists.

    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final chat in chats.docs) {
      await _deleteSubcollection(chat.reference, 'messages');
      await chat.reference.delete();
    }

    final userRef = _db.collection('users').doc(uid);
    await _deleteFollowTraces(uid, userRef, includeCollectionGroupSweep: true);
    await _deleteSubcollection(userRef, 'followers');
    await _deleteSubcollection(userRef, 'following');
    await _deleteSubcollection(userRef, 'reposts');
    await _deleteSubcollection(userRef, 'saved');
    await _deleteSubcollection(userRef, 'savedTranslations');

    await _deleteSubcollection(
        _db.collection('notifications').doc(uid), 'items');

    final regs = await _db
        .collection('eventRegistrations')
        .where('userUid', isEqualTo: uid)
        .get();
    for (final r in regs.docs) {
      await r.reference.delete();
    }

    await userRef.delete();

    if (email.isNotEmpty) {
      await _db.collection('blacklist').doc(email).set({
        'email': email,
        'uid': uid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    }

    // NOTE: the target user's Firebase Auth record cannot be deleted from
    // the client SDK (only the user themselves can call user.delete()).
    // Until the project is on the Blaze plan and the adminDeleteUser Cloud
    // Function is deployed, the Auth record remains and the email stays
    // locked. The blacklist write above lets the signup flow surface a
    // clear "this email was deleted" message.
  }

  /// Best-effort self-delete: the user removes their own data (what Firestore
  /// rules permit) and their Firebase Auth user. Leaves cross-user traces
  /// (followers on others, likes on others' posts) since collection-group
  /// writes aren't permitted for non-admin callers.
  ///
  /// Without Cloud Functions (Spark plan), the Firebase Auth record cannot
  /// be deleted reliably — `user.delete()` requires a recent login. To still
  /// free up the email so the user can re-register, we first rename the Auth
  /// account's email to a junk address on the reserved `.invalid` TLD
  /// (RFC 2606), then attempt the delete. Even if the delete fails, the
  /// real email is no longer attached to any Auth record, so the next
  /// `createUserWithEmailAndPassword` with that email will succeed.
  Future<void> selfDeleteCurrentUser(String uid) async {
    // Capture the email FIRST so we can blacklist it even if some downstream
    // step fails. This is what stops the user from signing back in (via
    // Google, Apple, or a recreated email/password account).
    final userRef = _db.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final email = (userSnap.data()?['email'] as String?) ?? '';
    if (email.isNotEmpty) {
      try {
        await _db.collection('blacklist').doc(email).set({
          'email': email,
          'uid': uid,
          'deletedAt': FieldValue.serverTimestamp(),
          'selfDeleted': true,
        });
      } catch (_) {
        // Best-effort — if rules reject the write the auth-account delete
        // below is the only remaining gate.
      }
    }

    // ── 1. The user's own posts (and every nested subcollection) ──────────
    final posts =
        await _db.collection('posts').where('authorUid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await _deleteSubcollection(post.reference, 'likes');
      await _deleteSubcollection(post.reference, 'reposts');
      // Comments under the post can themselves have likes / reactions —
      // sweep those before deleting each comment, then the comment.
      final comments = await post.reference.collection('comments').get();
      for (final c in comments.docs) {
        await _deleteSubcollection(c.reference, 'likes');
        await _deleteSubcollection(c.reference, 'reactions');
        await c.reference.delete();
      }
      await post.reference.delete();
    }

    // ── 2. The user's own stories (and nested subcollections) ─────────────
    final stories = await _db
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    for (final story in stories.docs) {
      await _deleteSubcollection(story.reference, 'viewers');
      await _deleteSubcollection(story.reference, 'likes');
      final sComments = await story.reference.collection('comments').get();
      for (final c in sComments.docs) {
        await _deleteSubcollection(c.reference, 'likes');
        await c.reference.delete();
      }
      await story.reference.delete();
    }

    // ── 3. The user's traces on OTHER people's content ────────────────────
    // Comments, likes, reposts and reactions the user left anywhere. The
    // collection-group reads are scoped by the loosened rules to the caller's
    // own docs only (authorUid / doc-id == uid), so this never touches
    // anyone else's data. Best-effort per group: a missing composite index
    // or a permission edge shouldn't abort the whole self-delete.
    await _deleteOwnCommentsEverywhere(uid);
    await _deleteOwnTraceByDocId('likes', uid);
    await _deleteOwnTraceByDocId('reposts', uid);
    await _deleteOwnTraceByDocId('reactions', uid);

    // ── 4. Direct-message chats — delete the WHOLE conversation for both ───
    // sides (messages + reactions + polls + the chat doc itself).
    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final chat in chats.docs) {
      // Messages (each may have a reactions subcollection).
      final messages = await chat.reference.collection('messages').get();
      for (final m in messages.docs) {
        await _deleteSubcollection(m.reference, 'reactions');
        await m.reference.delete();
      }
      // Polls (each may have a votes subcollection).
      final polls = await chat.reference.collection('polls').get();
      for (final p in polls.docs) {
        await _deleteSubcollection(p.reference, 'votes');
        await p.reference.delete();
      }
      // Finally the chat container — must come AFTER the messages above,
      // because the message-delete rule reads the (still-existing) chat doc
      // to verify participation.
      await chat.reference.delete();
    }

    // ── 5. Event registrations the user submitted ─────────────────────────
    final regs = await _db
        .collection('eventRegistrations')
        .where('userUid', isEqualTo: uid)
        .get();
    for (final r in regs.docs) {
      await r.reference.delete();
    }

    // ── 6. Event-group-chat memberships (leave every group) ───────────────
    // Find membership docs via the collection group, then delete each one
    // (rules allow a user to delete their own member doc).
    try {
      final memberships = await _db
          .collectionGroup('members')
          .where('uid', isEqualTo: uid)
          .get();
      for (final m in memberships.docs) {
        await m.reference.delete();
      }
    } catch (_) {
      // Best-effort — missing index or no memberships.
    }

    // ── 7. "Who viewed my profile" traces the user left on OTHER profiles ─
    try {
      final visits = await _db
          .collectionGroup('visitors')
          .where('uid', isEqualTo: uid)
          .get();
      for (final v in visits.docs) {
        await v.reference.delete();
      }
    } catch (_) {
      // The visitor doc id is the visitor's uid, so even without the `uid`
      // field this is bounded; ignore if the query/index isn't available.
    }

    // ── 8. Remove the user from other people's follow lists ───────────────
    await _deleteFollowTraces(uid, userRef);

    // ── 9. The user's own subcollections ──────────────────────────────────
    await _deleteSubcollection(userRef, 'followers');
    await _deleteSubcollection(userRef, 'following');
    await _deleteSubcollection(userRef, 'reposts');
    await _deleteSubcollection(userRef, 'saved');
    await _deleteSubcollection(userRef, 'savedTranslations');
    await _deleteSubcollection(userRef, 'visitors');

    await _deleteSubcollection(
        _db.collection('notifications').doc(uid), 'items');

    // ── 10. Custom stickers (Firestore packs + Firebase Storage .webp) ────
    try {
      await StickerService().deleteAllStickers(uid);
    } catch (e) {
      debugPrint('selfDelete: sticker deletion failed (continuing): $e');
    }

    // ── 11. The user's uploaded media in Supabase Storage ─────────────────
    // Runs BEFORE the Auth-email rename below so the Firebase ID token the
    // edge function verifies is still valid. Best-effort: a Storage failure
    // must not block freeing the account's email / Auth record.
    try {
      await StorageService().deleteAllMyMedia();
    } catch (e) {
      debugPrint('selfDelete: media deletion failed (continuing): $e');
    }

    // ── 12. Finally, the user document itself ─────────────────────────────
    await userRef.delete();

    // Free the email in Firebase Auth by renaming the account to a junk
    // address on the reserved .invalid TLD. This works without Cloud
    // Functions and survives session-age constraints differently than
    // delete: only email/password users can re-auth in-app, but the
    // rename itself frees the email even if a subsequent delete fails.
    await _freeAuthEmail(uid: uid, originalEmail: email);
  }

  /// Renames the current user's Auth email to a junk address so the real
  /// email is freed for re-signup, then attempts to delete the Auth user.
  /// Caller is responsible for any UI re-auth flow before invoking this.
  Future<void> _freeAuthEmail({
    required String uid,
    required String originalEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) return;

    // .invalid is a reserved TLD (RFC 2606) — guaranteed to not exist and
    // not collide with any real user. Including the uid keeps each junk
    // address unique so multiple deleted accounts don't clash with each
    // other on Firebase Auth's email-uniqueness constraint.
    final junkEmail = 'deleted+$uid@coil.invalid';
    try {
      // verifyBeforeUpdateEmail is the modern API but it sends a
      // confirmation email and doesn't apply the change until the user
      // clicks the link — useless here since we want the rename to take
      // effect immediately. updateEmail applies the change synchronously
      // (deprecated but still functional on current SDK versions).
      // ignore: deprecated_member_use
      await user.updateEmail(junkEmail);
    } on FirebaseAuthException catch (e) {
      // `requires-recent-login` is the common failure here — surface it
      // so the UI can prompt re-auth. Other codes get logged for triage.
      debugPrint(
        'Could not rename Auth email for $uid ($originalEmail): '
        '${e.code} ${e.message}',
      );
      rethrow;
    }

    // With the real email freed, try to delete the Auth record too. If
    // this fails (e.g. requires-recent-login), the user still benefits:
    // the orphan record only carries the .invalid email and no real
    // address is blocked.
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Auth user.delete() failed for $uid (email already freed): '
        '${e.code} ${e.message}',
      );
    }
  }

  Future<void> _deleteSubcollection(
      DocumentReference parent, String subcollection) async {
    final snap = await parent.collection(subcollection).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  /// Self-delete helper: deletes every comment authored by [uid] anywhere in
  /// the database (post comments, story comments, nested replies). Uses a
  /// `collectionGroup('comments')` query filtered to the caller's own
  /// `authorUid`, which the loosened rules permit. Each comment may have its
  /// own `likes` / `reactions` subcollections; those are swept first.
  /// Best-effort: a missing composite index or permission edge logs and
  /// returns rather than aborting the whole account deletion.
  Future<void> _deleteOwnCommentsEverywhere(String uid) async {
    try {
      final snap = await _db
          .collectionGroup('comments')
          .where('authorUid', isEqualTo: uid)
          .get();
      for (final c in snap.docs) {
        await _deleteSubcollection(c.reference, 'likes');
        await _deleteSubcollection(c.reference, 'reactions');
        await c.reference.delete();
      }
    } catch (e) {
      debugPrint('selfDelete: could not sweep own comments: $e');
    }
  }

  /// Self-delete helper: deletes every doc in any `[group]` subcollection
  /// whose document id equals [uid]. For `likes`, `reposts`, and `reactions`
  /// the doc id IS the acting user's uid, so a `collectionGroup` read scoped
  /// by the loosened rules returns only the caller's own traces. We can't
  /// filter a collection group by document id directly, so we read the group
  /// (rules already restrict the result to `isSelf`) and delete each hit.
  /// Best-effort per group.
  Future<void> _deleteOwnTraceByDocId(String group, String uid) async {
    try {
      final snap = await _db.collectionGroup(group).get();
      for (final doc in snap.docs) {
        if (doc.id == uid) {
          await doc.reference.delete();
        }
      }
    } catch (e) {
      debugPrint('selfDelete: could not sweep own $group: $e');
    }
  }

  Future<void> _deleteFollowTraces(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef, {
    bool includeCollectionGroupSweep = false,
  }) async {
    final refs = <String, DocumentReference<Map<String, dynamic>>>{};

    void add(DocumentReference<Map<String, dynamic>> ref) {
      refs[ref.path] = ref;
    }

    final followerSnap = await userRef.collection('followers').get();
    for (final doc in followerSnap.docs) {
      add(_db.collection('users').doc(doc.id).collection('following').doc(uid));
    }

    final followingSnap = await userRef.collection('following').get();
    for (final doc in followingSnap.docs) {
      add(_db.collection('users').doc(doc.id).collection('followers').doc(uid));
    }

    if (includeCollectionGroupSweep) {
      final followersOfOthers = await _db
          .collectionGroup('followers')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in followersOfOthers.docs) {
        add(doc.reference);
      }

      final followingOfOthers = await _db
          .collectionGroup('following')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in followingOfOthers.docs) {
        add(doc.reference);
      }
    }

    await _deleteRefsInBatches(refs.values);
  }

  Future<void> _deleteRefsInBatches(
    Iterable<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    var batch = _db.batch();
    var writes = 0;

    for (final ref in refs) {
      batch.delete(ref);
      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }

    if (writes > 0) await batch.commit();
  }

  // -------- Blacklist --------
  Stream<List<Map<String, dynamic>>> streamBlacklist() {
    return _db
        .collection('blacklist')
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Future<void> removeFromBlacklist(String email) =>
      _db.collection('blacklist').doc(email).delete();

  // -------- Posts --------
  Stream<List<Map<String, dynamic>>> streamAllPosts({int limit = 100}) {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  /// Normal social posts only (excludes discuss/Q&A posts where postType=qa).
  Stream<List<Map<String, dynamic>>> streamRegularPosts({int limit = 100}) {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit * 4)
        .snapshots()
        .map((s) {
      final filtered = s.docs
          .where((d) => (d.data()['postType'] as String?) != 'qa')
          .map((d) => {...d.data(), 'id': d.id})
          .toList();
      if (filtered.length <= limit) return filtered;
      return filtered.take(limit).toList();
    });
  }

  /// Discuss/Q&A posts only (postType == qa).
  Stream<List<Map<String, dynamic>>> streamDiscussPosts({int limit = 100}) {
    return _db
        .collection('posts')
        .where('postType', isEqualTo: 'qa')
        .limit(limit)
        .snapshots()
        .map((s) {
      final out = s.docs.map((d) => {...d.data(), 'id': d.id}).toList()
        ..sort((a, b) {
          final at = (a['createdAt'] as Timestamp?)?.toDate();
          final bt = (b['createdAt'] as Timestamp?)?.toDate();
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      return out;
    });
  }

  /// Delete a post as admin, properly updating author's postsCount.
  Future<void> deletePost(String postId) =>
      PostService().deletePostAsAdmin(postId);

  Stream<List<PostReport>> streamPostReports({int limit = 200}) {
    return _db
        .collection('postReports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(PostReport.fromDoc).toList());
  }

  Future<void> setPostReportResolved(String id, bool resolved) =>
      _db.collection('postReports').doc(id).update({
        'resolved': resolved,
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });

  Future<void> deletePostReport(String id) =>
      _db.collection('postReports').doc(id).delete();

  Stream<List<PostReport>> streamDiscussReports({int limit = 200}) {
    return _db
        .collection('discussReports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(PostReport.fromDoc).toList());
  }

  Future<void> setDiscussReportResolved(String id, bool resolved) =>
      _db.collection('discussReports').doc(id).update({
        'resolved': resolved,
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });

  Future<void> deleteDiscussReport(String id) =>
      _db.collection('discussReports').doc(id).delete();

  Stream<List<UserProfileReport>> streamUserProfileReports({int limit = 200}) {
    return _db
        .collection('userReports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(UserProfileReport.fromDoc).toList());
  }

  Future<void> setUserProfileReportResolved(String id, bool resolved) =>
      _db.collection('userReports').doc(id).update({
        'resolved': resolved,
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });

  Future<void> deleteUserProfileReport(String id) =>
      _db.collection('userReports').doc(id).delete();

  // -------- Comment reports --------
  Stream<List<CommentReport>> streamCommentReports({int limit = 200}) {
    return _db
        .collection('commentReports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(CommentReport.fromDoc).toList());
  }

  Future<void> setCommentReportResolved(String id, bool resolved) =>
      _db.collection('commentReports').doc(id).update({
        'resolved': resolved,
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });

  Future<void> deleteCommentReport(String id) =>
      _db.collection('commentReports').doc(id).delete();

  // -------- Events --------
  Stream<List<AdminEvent>> streamEvents() async* {
    List<AdminEvent> apiEvents = [];
    try {
      final res = await ApiClient.instance.get('/events', queryParams: {'limit': '100'});
      if (res is List) {
        apiEvents = res
            .whereType<Map<String, dynamic>>()
            .map(AdminEvent.fromJson)
            .toList();
        if (apiEvents.isNotEmpty) {
          yield apiEvents;
        }
      }
    } catch (e) {
      debugPrint('[AdminService] streamEvents API fetch error: $e');
    }

    yield* _db
        .collection('events')
        .snapshots()
        .map((s) {
          final firestoreEvents = s.docs.map(AdminEvent.fromDoc).toList();
          final mergedMap = <String, AdminEvent>{};
          for (final ev in apiEvents) {
            mergedMap[ev.id] = ev;
          }
          for (final ev in firestoreEvents) {
            mergedMap[ev.id] = ev;
          }
          final list = mergedMap.values.toList()
            ..sort((a, b) {
              final at = a.createdAt;
              final bt = b.createdAt;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
          return list;
        })
        .handleError((e) {
          debugPrint('[AdminService] Firestore events stream error: $e');
        });
  }

  /// Events filtered to those created by [uid]. Used by the org_admin
  /// role so an organization only sees / manages the events they
  /// posted themselves, never anyone else's.
  Stream<List<AdminEvent>> streamEventsCreatedBy(String uid) async* {
    List<AdminEvent> apiEvents = [];
    try {
      final res = await ApiClient.instance.get('/events', queryParams: {'limit': '100'});
      if (res is List) {
        apiEvents = res
            .whereType<Map<String, dynamic>>()
            .map(AdminEvent.fromJson)
            .where((e) => e.createdByUid == uid)
            .toList();
        if (apiEvents.isNotEmpty) {
          yield apiEvents;
        }
      }
    } catch (e) {
      debugPrint('[AdminService] streamEventsCreatedBy API fetch error: $e');
    }

    yield* _db
        .collection('events')
        .where('createdByUid', isEqualTo: uid)
        .snapshots()
        .map((s) {
          final firestoreEvents = s.docs.map(AdminEvent.fromDoc).toList();
          final mergedMap = <String, AdminEvent>{};
          for (final ev in apiEvents) {
            mergedMap[ev.id] = ev;
          }
          for (final ev in firestoreEvents) {
            mergedMap[ev.id] = ev;
          }
          final list = mergedMap.values.toList()
            ..sort((a, b) {
              final at = a.createdAt;
              final bt = b.createdAt;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
          return list;
        })
        .handleError((e) {
          debugPrint('[AdminService] Firestore streamEventsCreatedBy error: $e');
        });
  }

  Future<String> createEvent({
    required String title,
    required String subtitle,
    required String location,
    required String description,
    required String link,
    required String phone,
    required String email,
    required List<String> imageUrls,
    DateTime? deadlineAt,
    String eventType = '',
    String country = '',
    String funds = '',
    double? lat,
    double? lng,
  }) async {
    // Stamp the creator so org_admin users only see/manage their own
    // events (full admins still see everything via streamEvents()).
    // Also required by Firestore rules to authorize org_admin updates
    // and deletes.
    final creatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref = await _db.collection('events').add({
      'title': title,
      'subtitle': subtitle,
      'location': location,
      'description': description,
      'link': link,
      'phone': phone,
      'email': email,
      'imageUrls': imageUrls,
      if (deadlineAt != null) 'deadline': Timestamp.fromDate(deadlineAt),
      'eventType': eventType,
      if (lat != null && lng != null) 'geo': {'lat': lat, 'lng': lng},
      // Lower-cased first segment of the location, kept for legacy callers.
      'locationCity': location.split(',').first.trim().toLowerCase(),
      // `country` is the admin's chosen label (original casing);
      // `locationCountry` is its lower-cased form, used by the event-notification
      // fan-out to match against users' selected countries.
      'country': country.trim(),
      'locationCountry': country.trim().toLowerCase(),
      'funds': funds.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': creatorUid,
    });

    // Spark-plan stand-in for the `onEventCreate` Cloud Function: fan the
    // `new_event` notification out to matching users right here, from the
    // admin's device. Best-effort — a failure here mustn't fail event
    // creation. (On Blaze, the Cloud Function would also do this; the
    // deterministic doc id `new_event_<eventId>` keeps it idempotent if both
    // ever ran.)
    try {
      await _fanOutNewEventNotifications(
        eventId: ref.id,
        title: title.trim(),
        subtitle: location.trim(),
        eventType: eventType.trim(),
        eventCountry: country.trim().toLowerCase(),
      );
    } catch (_) {
      // Swallow — the event still exists; notifications just didn't go out.
    }

    return ref.id;
  }

  /// Writes a `new_event` notification doc to every non-suspended user whose
  /// `eventNotifPrefs` matches the event. Mirrors `functions/src/events.ts`.
  Future<void> _fanOutNewEventNotifications({
    required String eventId,
    required String title,
    required String subtitle,
    required String eventType,
    required String eventCountry,
  }) async {
    final usersSnap = await _db.collection('users').get();

    bool wants(Map<String, dynamic> u) {
      if (u['suspended'] == true) return false;
      final prefs = (u['eventNotifPrefs'] as Map<String, dynamic>?) ?? const {};
      // Legacy 'cities' mode counts as on; its city list is no longer used.
      if ((prefs['mode'] as String?) == 'off') return false;

      // Policy: when the admin doesn't pick a type or country, the event is
      // treated as "general" and reaches every user whose notifications are
      // on, regardless of their type/country filters. The previous strict
      // matching silently filtered out everyone with a non-empty filter list
      // whenever an admin forgot to set a type, which made the whole
      // notification pipeline look broken from the user's side.
      final types = ((prefs['types'] as List?)?.map((e) => e.toString()) ??
              const <String>[])
          .where((t) => t.trim().isNotEmpty)
          .toList();
      final countries = ((prefs['countries'] as List?)
                  ?.map((e) => e.toString().trim().toLowerCase()) ??
              const <String>[])
          .where((c) => c.isNotEmpty)
          .toList();

      // Matching policy: notify if the event matches the selected type OR
      // the selected country. Empty list means "all" for that dimension.
      final typePass =
          types.isEmpty || eventType.isEmpty || types.contains(eventType);
      final countryPass = countries.isEmpty ||
          eventCountry.isEmpty ||
          countries.contains(eventCountry);
      return typePass || countryPass;
    }

    var batch = _db.batch();
    var writes = 0;
    for (final doc in usersSnap.docs) {
      if (!wants(doc.data())) continue;
      final notifRef = _db
          .collection('notifications')
          .doc(doc.id)
          .collection('items')
          .doc('new_event_$eventId');
      batch.set(notifRef, {
        'type': 'new_event',
        'actorUid': '',
        'targetId': eventId,
        'title': title,
        'subtitle': subtitle,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      writes++;
      // Firestore batches cap at 500 writes.
      if (writes >= 450) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Keep the city search key in sync whenever the location changes.
    if (payload['location'] is String) {
      payload['locationCity'] =
          (payload['location'] as String).split(',').first.trim().toLowerCase();
    }
    // Keep the matching key in sync with the chosen country label.
    if (payload['country'] is String) {
      final c = (payload['country'] as String).trim();
      payload['country'] = c;
      payload['locationCountry'] = c.toLowerCase();
    }
    if (payload['deadline'] is DateTime) {
      payload['deadline'] = Timestamp.fromDate(payload['deadline'] as DateTime);
    }
    await _db.collection('events').doc(id).update(payload);
  }

  /// Delete an event.
  Future<void> deleteEvent(String id) async {
    await _deleteNewEventNotifications(id);
    await _deleteEventChatArtifacts(id);
    final batch = _db.batch();
    batch.delete(_db.collection('events').doc(id));
    await batch.commit();
  }

  /// How many events the given user has created. Used by the admin
  /// "revoke event manager" flow to decide whether to offer the
  /// "also delete their events" prompt.
  Future<int> countEventsCreatedBy(String uid) async {
    final snap = await _db
        .collection('events')
        .where('createdByUid', isEqualTo: uid)
        .get();
    return snap.docs.length;
  }

  /// Deletes every event created by [uid], reusing [deleteEvent] so each
  /// event's notifications and chat artifacts are swept too. Best-effort
  /// per event: one failing delete doesn't abort the sweep. Returns the
  /// number of events deleted.
  Future<int> deleteEventsCreatedBy(String uid) async {
    final snap = await _db
        .collection('events')
        .where('createdByUid', isEqualTo: uid)
        .get();
    var deleted = 0;
    for (final doc in snap.docs) {
      try {
        await deleteEvent(doc.id);
        deleted++;
      } catch (e) {
        debugPrint('deleteEventsCreatedBy: failed for ${doc.id}: $e');
      }
    }
    return deleted;
  }

  Future<void> _deleteEventChatArtifacts(String eventId) async {
    final chatRef = _db.collection('eventChats').doc(eventId);
    await _deleteCollectionDocs(chatRef.collection('messages'));
    await _deleteCollectionDocs(chatRef.collection('members'));
    await chatRef.delete().catchError((_) {});
  }

  Future<void> _deleteCollectionDocs(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    while (true) {
      final snap = await col.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) return;
    }
  }

  Future<void> _deleteNewEventNotifications(String eventId) async {
    final usersSnap = await _db.collection('users').get();
    var batch = _db.batch();
    var writes = 0;

    for (final userDoc in usersSnap.docs) {
      final notifRef = _db
          .collection('notifications')
          .doc(userDoc.id)
          .collection('items')
          .doc('new_event_$eventId');
      final notifSnap = await notifRef.get();
      if (!notifSnap.exists) continue;
      batch.delete(notifRef);
      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }

    if (writes > 0) await batch.commit();
  }
}
