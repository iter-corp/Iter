import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/post_card.dart';
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
                    color: context.borderColor,
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
                Expanded(
                  child: uids.isEmpty
                      ? Center(
                          child: Text(
                            'No users yet',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: uids.length,
                          separatorBuilder: (_, __) => const SizedBox.shrink(),
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
                                final avatarUrl = data?['avatarUrl'] as String?;
                                return ListTile(
                                  onTap: () {
                                    Navigator.pop(context);
                                    openUserProfile(context, uid: uid);
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: context.inputFill,
                                    backgroundImage: avatarUrl != null
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl == null
                                        ? const Icon(Icons.person, size: 18)
                                        : null,
                                  ),
                                  title: Text(
                                    (data?['username'] as String?) ?? uid,
                                  ),
                                  subtitle: Text(
                                    (data?['handle'] as String?) ?? '',
                                    style:
                                        TextStyle(color: context.textSecondary),
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
    final currentUid = (ref.watch(authStateProvider).value ??
            ref.watch(authServiceProvider).currentUser)
        ?.uid;
    final followersAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followersProvider(currentUid));
    final followingAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followingProvider(currentUid));

    return Scaffold(
      backgroundColor: context.cardBg,
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
                  followers: followersAsync.valueOrNull?.length ??
                      (user['followersCount'] as int?) ??
                      0,
                  following: followingAsync.valueOrNull?.length ??
                      (user['followingCount'] as int?) ??
                      0,
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
                if (currentUid != null)
                  _tabContent(currentUid)
                else
                  const ProfileEmpty(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabContent(String uid) {
    switch (selectedTab) {
      case 0:
        return UserPostsGrid(uid: uid);
      case 1:
        return UserRepostsGrid(uid: uid);
      case 2:
        return UserSavedGrid(uid: uid);
      default:
        return UserPostsGrid(uid: uid);
    }
  }

  void _showSettings(BuildContext context) {
    final isAdmin = ref.read(isAdminProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Privacy toggle
              Consumer(
                builder: (context, ref, _) {
                  final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
                  final isPrivate =
                      (userDoc?['isPrivate'] as bool?) ?? false;
                  return ListTile(
                    leading: Icon(
                      isPrivate ? Icons.lock_outline : Icons.lock_open,
                      color: AppColors.purple,
                    ),
                    title: const Text('Private account'),
                    subtitle: Text(
                      isPrivate
                          ? 'Only followers can see your posts'
                          : 'Anyone can see your posts',
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary),
                    ),
                    trailing: Switch.adaptive(
                      value: isPrivate,
                      activeTrackColor: AppColors.purple,
                      onChanged: (val) async {
                        final uid =
                            ref.read(authServiceProvider).currentUser?.uid;
                        if (uid == null) return;
                        await ref
                            .read(userServiceProvider)
                            .updateUser(uid, {'isPrivate': val});
                      },
                    ),
                    onTap: () async {
                      final uid =
                          ref.read(authServiceProvider).currentUser?.uid;
                      if (uid == null) return;
                      await ref
                          .read(userServiceProvider)
                          .updateUser(uid, {'isPrivate': !isPrivate});
                    },
                  );
                },
              ),
              // Dark mode
              Consumer(
                builder: (context, ref, _) {
                  final isDark =
                      ref.watch(themeModeProvider) == ThemeMode.dark;
                  return ListTile(
                    leading: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: isDark ? Colors.amber : Colors.grey,
                    ),
                    title: const Text('Dark mode'),
                    trailing: Switch.adaptive(
                      value: isDark,
                      activeTrackColor: AppColors.purple,
                      onChanged: (_) =>
                          ref.read(themeModeProvider.notifier).toggle(),
                    ),
                    onTap: () =>
                        ref.read(themeModeProvider.notifier).toggle(),
                  );
                },
              ),
              // Blocked users
              ListTile(
                leading:
                    const Icon(Icons.block, color: Color(0xFFD27B2B)),
                title: const Text('Blocked users'),
                trailing: Icon(Icons.chevron_right,
                    color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  _showBlockedUsers(context);
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.shield_outlined,
                      color: Color(0xFF7E3BE8)),
                  title: const Text('Admin panel',
                      style: TextStyle(
                        color: Color(0xFF7E3BE8),
                        fontWeight: FontWeight.w600,
                      )),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/admin');
                  },
                ),
              Divider(color: context.borderColor, height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Log out',
                    style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authServiceProvider).signOut();
                  ref.invalidate(adminConfigProvider);
                  ref.invalidate(adminPostsProvider);
                  ref.invalidate(adminEventsProvider);
                  ref.invalidate(blacklistProvider);
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever,
                    color: Colors.redAccent),
                title: const Text('Delete account',
                    style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text(
                    'Permanently remove your account and all your data.'),
                onTap: () => _confirmDeleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockedUsers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Blocked Users',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final blockedAsync =
                        ref.watch(blockedUsersProvider);
                    return blockedAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text('Error: $e')),
                      data: (blockedUids) {
                        if (blockedUids.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(Icons.block,
                                    size: 48,
                                    color: context.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'No blocked users',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: context.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Users you block will appear here.',
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: blockedUids.length,
                          itemBuilder: (context, index) {
                            final uid = blockedUids[index];
                            return _BlockedUserTile(uid: uid);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This permanently deletes your profile, posts, comments, stories, '
            'followers, and notifications. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete everything',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleting your account...')),
    );

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final uid = authUser.uid;

    try {
      await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
      await authUser.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'For security, please log out and log back in, then try again.'),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${e.message ?? e.code}')),
        );
      }
      return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
      return;
    }

    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // Auth user is already gone — signOut may no-op.
    }
    ref.invalidate(adminConfigProvider);
    ref.invalidate(adminPostsProvider);
    ref.invalidate(adminEventsProvider);
    ref.invalidate(blacklistProvider);
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      context.go('/login');
    }
  }
}

class UserPostsGrid extends ConsumerWidget {
  final String uid;
  const UserPostsGrid({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(userPostsProvider(uid));
    return postsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error: $e')),
      ),
      data: (posts) {
        if (posts.isEmpty) return const ProfileEmpty();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: posts.length,
          itemBuilder: (_, i) {
            final post = posts[i];
            final url = post.imageUrls.isNotEmpty ? post.imageUrls.first : null;
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(
                    posts: posts,
                    initialIndex: i,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: context.borderColor,
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: context.borderColor),
                          errorWidget: (_, __, ___) => Icon(
                            Icons.broken_image,
                            color: context.textSecondary,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Center(
                            child: Text(
                              post.caption,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: context.textPrimary),
                            ),
                          ),
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class UserRepostsGrid extends ConsumerWidget {
  final String uid;
  const UserRepostsGrid({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repostsAsync = ref.watch(userRepostsProvider(uid));
    return repostsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error: $e')),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return const _EmptyTab(
            icon: Icons.repeat,
            title: 'No reposts yet',
            subtitle: 'Posts you repost will show here.',
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: posts.length,
          itemBuilder: (_, i) {
            final post = posts[i];
            final url = post.imageUrls.isNotEmpty ? post.imageUrls.first : null;
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(
                    posts: posts,
                    initialIndex: i,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: context.borderColor,
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: context.borderColor),
                          errorWidget: (_, __, ___) => Icon(
                            Icons.broken_image,
                            color: context.textSecondary,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Center(
                            child: Text(
                              post.caption,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: context.textPrimary),
                            ),
                          ),
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class UserSavedGrid extends ConsumerWidget {
  final String uid;
  const UserSavedGrid({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(userSavedProvider(uid));
    return savedAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error: $e')),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return const _EmptyTab(
            icon: Icons.bookmark_border,
            title: 'No saved posts',
            subtitle: 'Save posts to view them here later.',
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: posts.length,
          itemBuilder: (_, i) {
            final post = posts[i];
            final url = post.imageUrls.isNotEmpty ? post.imageUrls.first : null;
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(
                    posts: posts,
                    initialIndex: i,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: context.borderColor,
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: context.borderColor),
                          errorWidget: (_, __, ___) => Icon(
                            Icons.broken_image,
                            color: context.textSecondary,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Center(
                            child: Text(
                              post.caption,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: context.textPrimary),
                            ),
                          ),
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: context.textMuted),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: context.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class PostDetailScreen extends StatefulWidget {
  final List<Post> posts;
  final int initialIndex;
  const PostDetailScreen({
    super.key,
    required this.posts,
    this.initialIndex = 0,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final ScrollController _controller;
  static const _itemExtent = 560.0; // approx PostCard height

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.initialIndex * _itemExtent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cardBg,
      appBar: AppBar(
        title: const Text('Posts'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: widget.posts.length,
        itemBuilder: (_, i) => PostCard(post: widget.posts[i]),
      ),
    );
  }
}

class _BlockedUserTile extends ConsumerWidget {
  final String uid;
  const _BlockedUserTile({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByUidProvider(uid));
    final data = userAsync.valueOrNull;
    final avatarUrl = data?['avatarUrl'] as String?;
    final username = (data?['username'] as String?) ?? uid;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.inputFill,
        backgroundImage:
            avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? const Icon(Icons.person, size: 18)
            : null,
      ),
      title: Text(username),
      trailing: SizedBox(
        height: 32,
        child: OutlinedButton(
          onPressed: () async {
            final currentUser =
                ref.read(authServiceProvider).currentUser;
            if (currentUser == null) return;
            await ref.read(blockServiceProvider).unblockUser(
                  currentUid: currentUser.uid,
                  targetUid: uid,
                );
          },
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: const Text(
            'Unblock',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
