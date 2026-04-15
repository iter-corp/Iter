import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
import '../widgets/profile_widget.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int selectedTab = 0;

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
                            final userAsync = ref
                                .watch(
                                  userServiceProvider,
                                )
                                .streamUser(uid);

                            return StreamBuilder<Map<String, dynamic>?>(
                              stream: userAsync,
                              builder: (context, snapshot) {
                                final data = snapshot.data;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey.shade200,
                                    child: const Icon(Icons.person, size: 18),
                                  ),
                                  title: Text(
                                    (data?['username'] as String?) ?? uid,
                                  ),
                                  subtitle: Text(
                                    (data?['handle'] as String?) ?? '',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                );
                              },
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
    final userAsync = ref.watch(currentUserDocProvider);
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final followersAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followersProvider(currentUid));
    final followingAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followingProvider(currentUid));

    return Scaffold(
      backgroundColor: Colors.white,
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No profile data'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              children: [
                ProfileCoverAvatar(
                  coverUrl: user['coverUrl'] as String?,
                  avatarUrl: user['avatarUrl'] as String?,
                ),
                ProfileNameBio(
                  name: (user['username'] as String?) ?? 'No name',
                  bio: (user['bio'] as String?) ?? '',
                ),
                ProfileStats(
                  followers: (user['followersCount'] as int?) ?? 0,
                  following: (user['followingCount'] as int?) ?? 0,
                  posts: (user['postsCount'] as int?) ?? 0,
                  onFollowersTap: () => _showUserListSheet(
                    title: 'Followers',
                    uids: followersAsync.value ?? const [],
                  ),
                  onFollowingTap: () => _showUserListSheet(
                    title: 'Following',
                    uids: followingAsync.value ?? const [],
                  ),
                ),
                ProfileButtons(
                  onSettings: () => _showSettings(context),
                ),
                ProfileTabBar(
                  selectedTab: selectedTab,
                  onTap: (i) => setState(() => selectedTab = i),
                ),
                const Divider(height: 1),
                const ProfileEmpty(),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log out', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
