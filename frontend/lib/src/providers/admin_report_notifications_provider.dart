import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/admin_service.dart';
import '../services/error_report_service.dart';
import 'admin_providers.dart';

const _kPostReportsSeenAtMs = 'admin_post_reports_seen_at_ms';
const _kDiscussReportsSeenAtMs = 'admin_discuss_reports_seen_at_ms';
const _kProfileReportsSeenAtMs = 'admin_profile_reports_seen_at_ms';
const _kErrorReportsSeenAtMs = 'admin_error_reports_seen_at_ms';

class AdminReportSeenState {
  final DateTime? postReportsSeenAt;
  final DateTime? discussReportsSeenAt;
  final DateTime? profileReportsSeenAt;
  final DateTime? errorReportsSeenAt;

  const AdminReportSeenState({
    this.postReportsSeenAt,
    this.discussReportsSeenAt,
    this.profileReportsSeenAt,
    this.errorReportsSeenAt,
  });

  AdminReportSeenState copyWith({
    DateTime? postReportsSeenAt,
    DateTime? discussReportsSeenAt,
    DateTime? profileReportsSeenAt,
    DateTime? errorReportsSeenAt,
    bool clearPost = false,
    bool clearDiscuss = false,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return AdminReportSeenState(
      postReportsSeenAt:
          clearPost ? null : (postReportsSeenAt ?? this.postReportsSeenAt),
      discussReportsSeenAt: clearDiscuss
          ? null
          : (discussReportsSeenAt ?? this.discussReportsSeenAt),
      profileReportsSeenAt: clearProfile
          ? null
          : (profileReportsSeenAt ?? this.profileReportsSeenAt),
      errorReportsSeenAt:
          clearError ? null : (errorReportsSeenAt ?? this.errorReportsSeenAt),
    );
  }
}

class AdminReportSeenNotifier extends StateNotifier<AdminReportSeenState> {
  AdminReportSeenNotifier() : super(const AdminReportSeenState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AdminReportSeenState(
      postReportsSeenAt: _fromMs(prefs.getInt(_kPostReportsSeenAtMs)),
      discussReportsSeenAt: _fromMs(prefs.getInt(_kDiscussReportsSeenAtMs)),
      profileReportsSeenAt: _fromMs(prefs.getInt(_kProfileReportsSeenAtMs)),
      errorReportsSeenAt: _fromMs(prefs.getInt(_kErrorReportsSeenAtMs)),
    );
  }

  DateTime _now() => DateTime.now();

  static DateTime? _fromMs(int? ms) {
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markPostReportsSeen() async {
    final now = _now();
    state = state.copyWith(postReportsSeenAt: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPostReportsSeenAtMs, now.millisecondsSinceEpoch);
  }

  Future<void> markDiscussReportsSeen() async {
    final now = _now();
    state = state.copyWith(discussReportsSeenAt: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDiscussReportsSeenAtMs, now.millisecondsSinceEpoch);
  }

  Future<void> markProfileReportsSeen() async {
    final now = _now();
    state = state.copyWith(profileReportsSeenAt: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kProfileReportsSeenAtMs, now.millisecondsSinceEpoch);
  }

  Future<void> markErrorReportsSeen() async {
    final now = _now();
    state = state.copyWith(errorReportsSeenAt: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kErrorReportsSeenAtMs, now.millisecondsSinceEpoch);
  }
}

final adminReportSeenProvider =
    StateNotifierProvider<AdminReportSeenNotifier, AdminReportSeenState>(
  (_) => AdminReportSeenNotifier(),
);

DateTime? _latestUnresolvedPostReportAt(List<PostReport> reports) {
  DateTime? latest;
  for (final r in reports) {
    if (r.resolved) continue;
    final at = r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}

DateTime? _latestUnresolvedProfileReportAt(List<UserProfileReport> reports) {
  DateTime? latest;
  for (final r in reports) {
    if (r.resolved) continue;
    final at = r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}

DateTime? _latestUnresolvedErrorReportAt(List<ErrorReport> reports) {
  DateTime? latest;
  for (final r in reports) {
    if (r.resolved) continue;
    final at = r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}

final hasNewPostReportsProvider = Provider<bool>((ref) {
  final seenAt = ref.watch(
    adminReportSeenProvider.select((s) => s.postReportsSeenAt),
  );
  final latest = ref.watch(postReportsProvider).maybeWhen(
        data: _latestUnresolvedPostReportAt,
        orElse: () => null,
      );
  if (latest == null) return false;
  if (seenAt == null) return true;
  return latest.isAfter(seenAt);
});

final hasNewDiscussReportsProvider = Provider<bool>((ref) {
  final seenAt = ref.watch(
    adminReportSeenProvider.select((s) => s.discussReportsSeenAt),
  );
  final latest = ref.watch(discussReportsProvider).maybeWhen(
        data: _latestUnresolvedPostReportAt,
        orElse: () => null,
      );
  if (latest == null) return false;
  if (seenAt == null) return true;
  return latest.isAfter(seenAt);
});

final hasNewProfileReportsProvider = Provider<bool>((ref) {
  final seenAt = ref.watch(
    adminReportSeenProvider.select((s) => s.profileReportsSeenAt),
  );
  final latest = ref.watch(userProfileReportsProvider).maybeWhen(
        data: _latestUnresolvedProfileReportAt,
        orElse: () => null,
      );
  if (latest == null) return false;
  if (seenAt == null) return true;
  return latest.isAfter(seenAt);
});

final hasNewErrorReportsProvider = Provider<bool>((ref) {
  final seenAt = ref.watch(
    adminReportSeenProvider.select((s) => s.errorReportsSeenAt),
  );
  final latest = ref.watch(errorReportsProvider).maybeWhen(
        data: _latestUnresolvedErrorReportAt,
        orElse: () => null,
      );
  if (latest == null) return false;
  if (seenAt == null) return true;
  return latest.isAfter(seenAt);
});

final hasAnyNewReportsProvider = Provider<bool>((ref) {
  return ref.watch(hasNewPostReportsProvider) ||
      ref.watch(hasNewDiscussReportsProvider) ||
      ref.watch(hasNewProfileReportsProvider) ||
      ref.watch(hasNewErrorReportsProvider);
});
