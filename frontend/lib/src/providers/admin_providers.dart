import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_service.dart';
import 'auth_providers.dart';

final adminServiceProvider = Provider<AdminService>((_) => AdminService());

final adminConfigProvider = StreamProvider<AdminConfig>(
  (ref) => ref.watch(adminServiceProvider).streamConfig(),
);

final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserDocProvider).value;
  return (user?['role'] as String?) == 'admin';
});

final adminUsersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, query) => ref.watch(adminServiceProvider).streamUsers(query: query),
);

final adminPostsProvider = StreamProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(adminServiceProvider).streamAllPosts(),
);

final adminEventsProvider = StreamProvider<List<AdminEvent>>(
  (ref) => ref.watch(adminServiceProvider).streamEvents(),
);
