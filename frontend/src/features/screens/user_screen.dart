import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../widgets/user_profile_widget.dart';

final _otherUserProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, uid) {
  return ref.watch(userServiceProvider).streamUser(uid);
});

class UserProfileScreen extends ConsumerStatefulWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  int selectedTab = 0;
  bool isFollowing = false;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(_otherUserProvider(widget.uid));

    return Scaffold(
      backgroundColor: Colors.white,
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('User not found'));
          }
          final username = (user['username'] as String?) ?? 'User';
          final handle = (user['handle'] as String?) ?? '';
          final avatar = (user['avatarUrl'] as String?) ?? '';
          const isPrivate = false;

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                UserCoverAvatar(
                  avatar: avatar,
                  posts: const [],
                  isPrivate: isPrivate,
                  onBack: () => Navigator.pop(context),
                ),
                UserNameBio(username: username, handle: handle),
                const UserStats(),
                UserButtons(
                  isFollowing: isFollowing,
                  isPrivate: isPrivate,
                  onFollowTap: () =>
                      setState(() => isFollowing = !isFollowing),
                ),
                UserTabBar(
                  selectedTab: selectedTab,
                  onTap: (i) => setState(() => selectedTab = i),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text("No posts yet",
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
