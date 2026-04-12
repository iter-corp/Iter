import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../widgets/profile_widget.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDocProvider);

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
              title: const Text('Log out',
                  style: TextStyle(color: Colors.red)),
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
