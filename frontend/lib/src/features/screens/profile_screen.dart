import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/admin_providers.dart';
import '../../providers/admin_report_notifications_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/contact_request_providers.dart';
import '../../providers/follow_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/theme_provider.dart';

import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/app_page_background.dart';
import '../widgets/post_card.dart';
import '../widgets/profile_widget.dart';
import 'blocked_users_screen.dart';
import 'profile_settings_screen.dart';
import 'qa_thread_screen.dart';

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
                            context.t.profileNoUsersYet,
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
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final isAdmin = ref.watch(isAdminProvider);
    final hasNewReports = ref.watch(hasAnyNewReportsProvider);
    final hasUnreadContact = ref.watch(hasUnreadContactRequestsProvider);
    final followersAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followersProvider(currentUid));
    final followingAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followingProvider(currentUid));
    final postsAsync = currentUid == null
        ? const AsyncValue<List<Post>>.data([])
        : ref.watch(userPostsProvider(currentUid));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (user) {
            if (user == null) {
              return Center(child: Text(context.t.profileNoProfileData));
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
                    name: (user['name'] as String?) ??
                        (user['username'] as String?) ??
                        'No name',
                    handle: (user['handle'] as String?) ??
                        ((user['username'] as String?) != null
                            ? '@${user['username']}'
                            : ''),
                    bio: (user['bio'] as String?) ?? '',
                    profession: (user['profession'] as String?) ?? '',
                    educationLevel: (user['academicLevel'] as String?) ?? '',
                    fieldOfStudy: (user['field'] as String?) ?? '',
                  ),
                  ProfileStats(
                    followers: followersAsync.valueOrNull?.length ??
                        (user['followersCount'] as int?) ??
                        0,
                    following: followingAsync.valueOrNull?.length ??
                        (user['followingCount'] as int?) ??
                        0,
                    posts: postsAsync.valueOrNull?.length ??
                        (user['postsCount'] as int?) ??
                        0,
                    onFollowersTap: () => _showUserListSheet(
                      title: context.t.followers,
                      uids: followersAsync.value ?? const [],
                    ),
                    onFollowingTap: () => _showUserListSheet(
                      title: context.t.following,
                      uids: followingAsync.value ?? const [],
                    ),
                  ),
                  ProfileButtons(
                    onSettings: () => _showSettings(context),
                    showSettingsNotificationDot:
                        isAdmin && (hasNewReports || hasUnreadContact),
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
      ),
    );
  }

  Widget _tabContent(String uid) {
    final child = switch (selectedTab) {
      0 => UserPostsGrid(uid: uid),
      1 => UserQaActivitySection(uid: uid),
      2 => UserRepostsGrid(uid: uid),
      3 => UserSavedGrid(uid: uid),
      _ => UserPostsGrid(uid: uid),
    };
    // Horizontal swipe to switch tabs (left = next, right = prev).
    // Threshold uses primaryVelocity so a quick flick reliably moves
    // tabs while a vertical scroll never accidentally triggers it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -250 && selectedTab < 3) {
          setState(() => selectedTab = selectedTab + 1);
        } else if (v > 250 && selectedTab > 0) {
          setState(() => selectedTab = selectedTab - 1);
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(
            begin: const Offset(0.04, 0.0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previous,
            if (current != null) current,
          ],
        ),
        child: KeyedSubtree(
          key: ValueKey(selectedTab),
          child: child,
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
    );
  }

  // ignore: unused_element
  void _legacyShowSettings(BuildContext context) {
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
                context.t.settings,
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
                  final isPrivate = (userDoc?['isPrivate'] as bool?) ?? false;
                  return ListTile(
                    leading: Icon(
                      isPrivate ? Icons.lock_outline : Icons.lock_open,
                      color: AppColors.purple,
                    ),
                    title: Text(context.t.privateAccount),
                    subtitle: Text(
                      isPrivate
                          ? context.t.profileOnlyFollowersCanSee
                          : context.t.profileAnyoneCanSee,
                      style:
                          TextStyle(fontSize: 12, color: context.textSecondary),
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
                  final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                  return ListTile(
                    leading: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: isDark ? Colors.amber : Colors.grey,
                    ),
                    title: Text(context.t.darkMode),
                    trailing: Switch.adaptive(
                      value: isDark,
                      activeTrackColor: AppColors.purple,
                      onChanged: (_) =>
                          ref.read(themeModeProvider.notifier).toggle(),
                    ),
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  );
                },
              ),
              // Blocked users
              ListTile(
                leading: const Icon(Icons.block, color: Color(0xFFD27B2B)),
                title: Text(context.t.blockedUsers),
                trailing:
                    Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  );
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.shield_outlined,
                      color: Color(0xFF7E3BE8)),
                  title: Text(context.t.profileAdminPanel,
                      style: const TextStyle(
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
                title: Text(context.t.logout,
                    style: const TextStyle(color: Colors.red)),
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
                leading:
                    const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: Text(context.t.deleteAccount,
                    style: const TextStyle(color: Colors.redAccent)),
                subtitle: Text(context.t.profileDeleteAccountSubtitle),
                onTap: () => _confirmDeleteAccount(context, ref),
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
        title: Text(context.t.profileDeleteAccountTitle),
        content: Text(context.t.profileDeleteAccountBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.profileDeleteEverything,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.profileDeletingAccount)),
    );

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final uid = authUser.uid;

    try {
      // selfDeleteCurrentUser renames the Auth email to a junk .invalid
      // address so the real email is freed for re-signup, then attempts
      // to delete the Auth record. The rename requires a recent login;
      // we prompt for re-auth and retry once if needed.
      await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (!context.mounted) return;
        final reAuthed = await _reauthBeforeDelete(context, authUser);
        if (!reAuthed) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.profileReauthRequired)),
            );
          }
          return;
        }
        try {
          await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
        } catch (e2) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.deleteFailed(e2))),
            );
          }
          return;
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.t.deleteFailed(e.message ?? e.code))),
          );
        }
        return;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.deleteFailed(e))),
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

  /// Prompts a password user for their current password and re-authenticates
  /// so the Auth-email rename inside selfDeleteCurrentUser can proceed.
  /// Returns true on success, false if the user cancelled or re-auth failed.
  /// For non-password accounts (Google / Apple) returns false — they'd need
  /// a different OAuth re-auth flow that we don't trigger from here.
  Future<bool> _reauthBeforeDelete(BuildContext context, User user) async {
    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');
    if (!isPasswordUser || user.email == null) return false;

    final passCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.settingsCurrentPassword),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: ctx.t.settingsCurrentPassword),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, passCtrl.text),
            child: Text(ctx.t.ok),
          ),
        ],
      ),
    );
    passCtrl.dispose();
    if (password == null || password.isEmpty) return false;

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }
}

/// Square thumbnail for a post grid cell. Renders, in priority order:
/// 1. the first image if the post has any,
/// 2. the first frame of the first video if the post is video-only,
/// 3. a caption-only fallback for text posts.
/// A small play badge overlays video thumbs so they're recognisable.
class PostThumbTile extends StatelessWidget {
  final Post post;
  const PostThumbTile({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    if (post.imageUrls.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: post.imageUrls.first,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: context.borderColor),
        errorWidget: (_, __, ___) =>
            Icon(Icons.broken_image, color: context.textSecondary),
      );
    }
    if (post.videoUrls.isNotEmpty) {
      return _VideoThumb(url: post.videoUrls.first);
    }
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Center(
        child: Text(
          post.caption,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.textPrimary),
        ),
      ),
    );
  }
}

/// Renders the first frame of a network video as a still thumbnail.
/// We initialise a VideoPlayerController, seek to 0, and never call play —
/// the plugin paints the decoded frame as the texture.
class _VideoThumb extends StatefulWidget {
  final String url;
  const _VideoThumb({required this.url});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    c.setVolume(0);
    c.initialize().then((_) async {
      if (!mounted) return;
      await c.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() {});
    }).catchError((_) {
      // Leave the placeholder visible on decode failure.
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          )
        else
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white70),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
            ),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 14),
          ),
        ),
      ],
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
        child: Center(child: Text(context.t.errorWithMessage(e))),
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
                  child: PostThumbTile(post: post),
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
    // Hide reposts whose author is in the viewer's block list — once
    // you block someone, their content shouldn't reappear via your own
    // profile's Reposts tab.
    final blockedSet =
        (ref.watch(blockedUsersProvider).valueOrNull ?? const <String>[])
            .toSet();
    return repostsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(context.t.errorWithMessage(e))),
      ),
      data: (allPosts) {
        final posts =
            allPosts.where((p) => !blockedSet.contains(p.authorUid)).toList();
        if (posts.isEmpty) {
          return _EmptyTab(
            icon: Icons.repeat,
            title: context.t.profileNoRepostsYet,
            subtitle: context.t.profileNoRepostsSubtitle,
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
                  child: PostThumbTile(post: post),
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
    final blockedSet =
        (ref.watch(blockedUsersProvider).valueOrNull ?? const <String>[])
            .toSet();
    return savedAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(context.t.errorWithMessage(e))),
      ),
      data: (allPosts) {
        final posts =
            allPosts.where((p) => !blockedSet.contains(p.authorUid)).toList();
        if (posts.isEmpty) {
          return _EmptyTab(
            icon: Icons.bookmark_border,
            title: context.t.profileNoSavedPosts,
            subtitle: context.t.profileNoSavedSubtitle,
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
                  child: PostThumbTile(post: post),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class UserQaActivitySection extends ConsumerStatefulWidget {
  final String uid;
  const UserQaActivitySection({super.key, required this.uid});

  @override
  ConsumerState<UserQaActivitySection> createState() =>
      _UserQaActivitySectionState();
}

class _UserQaActivitySectionState extends ConsumerState<UserQaActivitySection> {
  int _innerTab = 0; // 0 = asked, 1 = answered

  @override
  Widget build(BuildContext context) {
    final askedAsync = ref.watch(userQaAskedProvider(widget.uid));
    final answeredAsync = ref.watch(userQaAnsweredProvider(widget.uid));

    Widget listFor(AsyncValue<List<Post>> asyncPosts, {required bool asked}) {
      return asyncPosts.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(context.t.errorWithMessage(e))),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return _EmptyTab(
              icon: asked ? Icons.help_outline_rounded : Icons.rate_review,
              title: asked
                  ? context.t.profileNoThreadsStarted
                  : context.t.profileNoRepliesYet,
              subtitle: asked
                  ? context.t.profileNoThreadsStartedSubtitle
                  : context.t.profileNoRepliesSubtitle,
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = posts[i];
              final title = p.caption.trim().split('\n').first.trim();
              final time = context.t.timeAgo(p.createdAt);
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QaThreadScreen(
                      post: p,
                      highlightAuthorUid: asked ? null : widget.uid,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        asked ? Icons.help_outline_rounded : Icons.rate_review,
                        size: 18,
                        color: const Color(0xFF7E3BE8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty
                                  ? context.t.qaUntitledQuestion
                                  : title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$time • ${context.t.homeAnswersCount(p.commentsCount < 0 ? 0 : p.commentsCount)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.inputFill,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _InnerQaTab(
                    label: context.t.profileThreadsStarted,
                    selected: _innerTab == 0,
                    onTap: () => setState(() => _innerTab = 0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _InnerQaTab(
                    label: context.t.profileReplies,
                    selected: _innerTab == 1,
                    onTap: () => setState(() => _innerTab = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        _innerTab == 0
            ? listFor(askedAsync, asked: true)
            : listFor(answeredAsync, asked: false),
      ],
    );
  }
}

class _InnerQaTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _InnerQaTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: context.borderColor)
              : Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ),
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
        title: Text(context.t.posts),
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
