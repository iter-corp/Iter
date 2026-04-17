import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/post_providers.dart';
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
                                final avatarUrl =
                                    data?['avatarUrl'] as String?;
                                return ListTile(
                                  onTap: () {
                                    Navigator.pop(context);
                                    openUserProfile(context, uid: uid);
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey.shade200,
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
                const Divider(height: 1),
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
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin)
              ListTile(
                leading:
                    const Icon(Icons.shield_outlined, color: Color(0xFF7E3BE8)),
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
                  color: const Color(0xFFEDEDF2),
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: const Color(0xFFEDEDF2)),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
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
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black87),
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
                  color: const Color(0xFFEDEDF2),
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: const Color(0xFFEDEDF2)),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
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
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black87),
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
                  color: const Color(0xFFEDEDF2),
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: const Color(0xFFEDEDF2)),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
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
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black87),
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
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Posts'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
