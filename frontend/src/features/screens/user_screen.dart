import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
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
  bool _followBusy = false;

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    final currentUser = ref.read(authStateProvider).value;
    if (currentUser == null || _followBusy) return;

    setState(() => _followBusy = true);
    try {
      final service = ref.read(followServiceProvider);
      if (currentlyFollowing) {
        await service.unfollow(
          currentUid: currentUser.uid,
          targetUid: widget.uid,
        );
      } else {
        await service.follow(
          currentUid: currentUser.uid,
          targetUid: widget.uid,
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _showUserListSheet({required String title, required List<String> uids}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: uids.isEmpty
                      ? const Center(
                          child: Text(
                            'No users yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          itemCount: uids.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final uid = uids[index];
                            final userAsync =
                                ref.watch(_otherUserProvider(uid));
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey.shade200,
                                child: const Icon(Icons.person, size: 18),
                              ),
                              title: userAsync.when(
                                loading: () => const Text('Loading...'),
                                error: (_, __) => Text(uid),
                                data: (user) =>
                                    Text((user?['username'] as String?) ?? uid),
                              ),
                              subtitle: userAsync.when(
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                                data: (user) => Text(
                                  (user?['handle'] as String?) ?? '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(_otherUserProvider(widget.uid));
    final currentUser = ref.watch(authStateProvider).value;
    final isOwnProfile = currentUser?.uid == widget.uid;
    final isFollowingAsync = ref.watch(isFollowingProvider(widget.uid));
    final followersAsync = ref.watch(followersProvider(widget.uid));
    final followingAsync = ref.watch(followingProvider(widget.uid));

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
          final isFollowing = isFollowingAsync.value ?? false;
          final followers = (user['followersCount'] as int?) ?? 0;
          final following = (user['followingCount'] as int?) ?? 0;
          final posts = (user['postsCount'] as int?) ?? 0;

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
                UserStats(
                  followers: followers,
                  following: following,
                  posts: posts,
                  onFollowersTap: () => _showUserListSheet(
                    title: 'Followers',
                    uids: followersAsync.value ?? const [],
                  ),
                  onFollowingTap: () => _showUserListSheet(
                    title: 'Following',
                    uids: followingAsync.value ?? const [],
                  ),
                ),
                if (!isOwnProfile)
                  UserButtons(
                    isFollowing: isFollowing,
                    isPrivate: isPrivate,
                    onFollowTap:
                        _followBusy ? () {} : () => _toggleFollow(isFollowing),
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
