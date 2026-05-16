import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_service.dart';
import '../services/error_report_service.dart';
import 'auth_providers.dart';

final adminServiceProvider = Provider<AdminService>((_) => AdminService());

final adminConfigProvider = StreamProvider<AdminConfig>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamConfig();
});

final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserDocProvider).value;
  return (user?['role'] as String?) == 'admin';
});

final adminUsersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, query) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamUsers(query: query);
});

final adminPostsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamAllPosts();
});

final postReportsProvider = StreamProvider<List<PostReport>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  if (!ref.watch(isAdminProvider)) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamPostReports();
});

final discussReportsProvider = StreamProvider<List<PostReport>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  if (!ref.watch(isAdminProvider)) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamDiscussReports();
});

final userProfileReportsProvider =
    StreamProvider<List<UserProfileReport>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  if (!ref.watch(isAdminProvider)) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamUserProfileReports();
});

final errorReportAdminProvider =
    Provider<ErrorReportAdmin>((_) => ErrorReportAdmin());

final errorReportsProvider = StreamProvider<List<ErrorReport>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  if (!ref.watch(isAdminProvider)) return const Stream.empty();
  return ref.watch(errorReportAdminProvider).stream();
});

final adminEventsProvider = StreamProvider<List<AdminEvent>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamEvents();
});

final blacklistProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamBlacklist();
});
