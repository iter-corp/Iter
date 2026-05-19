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

/// True when the signed-in user has the limited event-posting role
/// granted via the contact-us "organization" flow. Lets the events
/// admin screen surface itself to them while keeping all other
/// admin tooling hidden.
final isOrgAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserDocProvider).value;
  return (user?['role'] as String?) == 'org_admin';
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

/// Every event in the system, newest first. Used by the public-facing
/// events page so all users see every event, regardless of who
/// created it. NOT role-scoped — see [manageableEventsProvider] for
/// the admin-screen filter.
final adminEventsProvider = StreamProvider<List<AdminEvent>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamEvents();
});

/// Events the signed-in user is allowed to manage from the admin
/// "Manage events" screen. Full admins see every event; org_admins
/// see only the events they themselves created. Mirrors the
/// Firestore rule on /events update/delete.
final manageableEventsProvider = StreamProvider<List<AdminEvent>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  if (ref.watch(isOrgAdminProvider) && !ref.watch(isAdminProvider)) {
    return ref
        .watch(adminServiceProvider)
        .streamEventsCreatedBy(user.uid);
  }
  return ref.watch(adminServiceProvider).streamEvents();
});

final blacklistProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(adminServiceProvider).streamBlacklist();
});
