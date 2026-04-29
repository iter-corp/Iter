import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/profile_visitor_providers.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/user_profile_widget.dart';
import 'chat_screen.dart';
import 'profile_screen.dart' show PostDetailScreen;

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
  bool _messageBusy = false;

  @override
  void initState() {
    super.initState();
    // Log a profile visit on the next frame so the owner can see who's
    // looked at their profile (and how recently). Best-effort — the
    // service swallows rule failures so this never blocks render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(profileVisitorServiceProvider).recordVisit(widget.uid);
    });
  }

  Future<void> _toggleFollow(bool currentlyFollowing, bool currentlyRequested, bool isPrivate) async {
    final currentUser = ref.read(authStateProvider).value ??
        ref.read(authServiceProvider).currentUser;
    if (currentUser == null || _followBusy) return;

    setState(() => _followBusy = true);
    try {
      final service = ref.read(followServiceProvider);
      if (currentlyFollowing || currentlyRequested) {
        await service.unfollow(
          currentUid: currentUser.uid,
          targetUid: widget.uid,
        );
      } else {
        await service.follow(
          currentUid: currentUser.uid,
          targetUid: widget.uid,
          isPrivate: isPrivate,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Follow action failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _openMessage(String otherName, String otherAvatar) async {
    final currentUser = ref.read(authStateProvider).value ??
        ref.read(authServiceProvider).currentUser;
    if (currentUser == null || _messageBusy) return;
    setState(() => _messageBusy = true);
    try {
      final chatId = await ref.read(chatServiceProvider).openChat(
            currentUid: currentUser.uid,
            otherUid: widget.uid,
          );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUid: widget.uid,
            otherName: otherName,
            otherAvatar: otherAvatar,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _messageBusy = false);
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
                            final userAsync =
                                ref.watch(_otherUserProvider(uid));
                            final avatarUrl =
                                userAsync.valueOrNull?['avatarUrl'] as String?;
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
                                  style:
                                      TextStyle(color: context.textSecondary),
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
    final currentUser = ref.watch(authStateProvider).value ??
        ref.watch(authServiceProvider).currentUser;
    final isOwnProfile = currentUser?.uid == widget.uid;
    final isFollowingAsync = ref.watch(isFollowingProvider(widget.uid));
    final isRequestedAsync = ref.watch(hasRequestedFollowProvider(widget.uid));
    final followersAsync = ref.watch(followersProvider(widget.uid));
    final followingAsync = ref.watch(followingProvider(widget.uid));
    
    final isBlockedAsync = ref.watch(isBlockedProvider(widget.uid));
    final isBlockedByAsync = ref.watch(isBlockedByProvider(widget.uid));

    return Scaffold(
      backgroundColor: context.cardBg,
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('User not found'));
          }
          final username = (user['username'] as String?) ?? 'User';
          final handle = (user['handle'] as String?) ?? '';
          final avatarUrl = user['avatarUrl'] as String?;
          final coverUrl = user['coverUrl'] as String?;
          final isPrivate = (user['isPrivate'] as bool?) ?? false;
          final isFollowing = isFollowingAsync.value ?? false;
          final isRequested = isRequestedAsync.value ?? false;
          final followers = followersAsync.valueOrNull?.length ??
              (user['followersCount'] as int?) ??
              0;
          final following = followingAsync.valueOrNull?.length ??
              (user['followingCount'] as int?) ??
              0;
          final posts = (user['postsCount'] as int?) ?? 0;

          final isBlocked = isBlockedAsync.value ?? false;
          final isBlockedBy = isBlockedByAsync.value ?? false;

          // If current user is blocked by target user, or blocked target user
          final hideContent = isBlocked || isBlockedBy;
          // If private and not following and not own profile
          final enforcePrivacy = isPrivate && !isFollowing && !isOwnProfile;

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                UserCoverAvatar(
                  avatarUrl: avatarUrl,
                  coverUrl: coverUrl,
                  isPrivate: isPrivate,
                  onBack: () => Navigator.pop(context),
                  showMenu: !isOwnProfile,
                  onBlockTap: () async {
                    if (currentUser == null) return;
                    try {
                      if (isBlocked) {
                        await ref.read(blockServiceProvider).unblockUser(
                              currentUid: currentUser.uid,
                              targetUid: widget.uid,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User unblocked')),
                          );
                        }
                      } else {
                        await ref.read(blockServiceProvider).blockUser(
                              currentUid: currentUser.uid,
                              targetUid: widget.uid,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User blocked')),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to block/unblock: $e\nDid you deploy the Firestore rules?',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  isBlocked: isBlocked,
                ),
                UserNameBio(
                  username: username,
                  handle: handle,
                  bio: (user['bio'] as String?) ?? '',
                  isPrivate: isPrivate,
                ),
                if (!hideContent) ...[
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
                    isPrivateAndNotFollowing: enforcePrivacy,
                  ),
                  if (!isOwnProfile && !isBlockedBy)
                    UserButtons(
                      isFollowing: isFollowing,
                      isRequested: isRequested,
                      isPrivate: isPrivate,
                      onFollowTap: _followBusy
                          ? () {}
                          : () => _toggleFollow(isFollowing, isRequested, isPrivate),
                      onMessageTap: _messageBusy
                          ? null
                          : () => _openMessage(username, avatarUrl ?? ''),
                    ),
                  if (enforcePrivacy)
                    const UserPrivateMessage()
                  else ...[
                    UserTabBar(
                      selectedTab: selectedTab,
                      onTap: (i) => setState(() => selectedTab = i),
                    ),
                    if (selectedTab == 0)
                      _UserPostsGrid(uid: widget.uid)
                    else
                      _UserRepostsGrid(uid: widget.uid),
                  ]
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 32),
                    child: Column(
                      children: [
                        Icon(
                          isBlockedBy ? Icons.person_off_outlined : Icons.block,
                          size: 36,
                          color: context.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isBlockedBy
                              ? 'User not found'
                              : 'You have blocked this user',
                          style: TextStyle(
                              fontSize: 16, color: context.textSecondary),
                        ),
                        if (isBlocked && !isBlockedBy) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Their posts, reposts and saved items are hidden, '
                            'and they can\'t message you.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.lock_open, size: 18),
                              label: const Text('Unblock'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB05ECC),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () async {
                                if (currentUser == null) return;
                                try {
                                  await ref
                                      .read(blockServiceProvider)
                                      .unblockUser(
                                        currentUid: currentUser.uid,
                                        targetUid: widget.uid,
                                      );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('User unblocked')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Failed to unblock: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserPostsGrid extends ConsumerWidget {
  final String uid;
  const _UserPostsGrid({required this.uid});

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
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text('No posts yet',
                  style: TextStyle(color: context.textSecondary)),
            ),
          );
        }
        return _postsGrid(context, posts);
      },
    );
  }
}

class _UserRepostsGrid extends ConsumerWidget {
  final String uid;
  const _UserRepostsGrid({required this.uid});

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
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text('No reposts yet',
                  style: TextStyle(color: context.textSecondary)),
            ),
          );
        }
        return _postsGrid(context, posts);
      },
    );
  }
}

Widget _postsGrid(BuildContext context, List<Post> posts) {
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
                    errorWidget: (_, __, ___) =>
                        Icon(Icons.broken_image, color: context.textSecondary),
                  )
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: Center(
                      child: Text(
                        post.caption,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 11, color: context.textPrimary),
                      ),
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
