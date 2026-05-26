import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
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
import 'profile_screen.dart' show PostDetailScreen, PostThumbTile;
import 'qa_thread_screen.dart';

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

  // Local overrides for instant UI feedback. When non-null, these take
  // precedence over the Firestore stream values until the stream catches up.
  bool? _localIsFollowing;
  bool? _localIsRequested;

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

  /// Clears local overrides so the Firestore stream becomes the sole
  /// source of truth again.
  void _clearLocalOverrides() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _localIsFollowing = null;
          _localIsRequested = null;
        });
      }
    });
  }

  Future<void> _toggleFollow(
      bool currentlyFollowing, bool currentlyRequested, bool isPrivate) async {
    final currentUser = ref.read(authStateProvider).value ??
        ref.read(authServiceProvider).currentUser;
    if (currentUser == null || _followBusy) return;

    // ── Optimistic local update (instant) ──
    if (currentlyFollowing || currentlyRequested) {
      // Unfollowing / cancelling request.
      setState(() {
        _followBusy = true;
        _localIsFollowing = false;
        _localIsRequested = false;
      });
    } else {
      // Following.
      setState(() {
        _followBusy = true;
        if (isPrivate) {
          _localIsFollowing = false;
          _localIsRequested = true;
          // No follower-count change for a pending request.
        } else {
          _localIsFollowing = true;
          _localIsRequested = false;
        }
      });
    }

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
      // Server confirmed — let the stream take over after a short grace.
      _clearLocalOverrides();
    } catch (e) {
      // Rollback local overrides on failure.
      if (mounted) {
        setState(() {
          _localIsFollowing = null;
          _localIsRequested = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.userFollowActionFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _reportProfile({
    required String targetUid,
    required String targetUsername,
    String? targetAvatar,
  }) async {
    // Keys are stable English values stored in Firestore; labels are
    // resolved to the active language only for display.
    const reasons = <String>[
      'Spam or scam profile',
      'Impersonation',
      'Harassment or bullying',
      'Hate speech',
      'Nudity or sexual content',
      'Violence or threats',
      'Something else',
    ];
    String reasonLabel(String key) {
      switch (key) {
        case 'Spam or scam profile':
          return context.t.userReportReasonSpam;
        case 'Impersonation':
          return context.t.userReportReasonImpersonation;
        case 'Harassment or bullying':
          return context.t.userReportReasonHarassment;
        case 'Hate speech':
          return context.t.userReportReasonHateSpeech;
        case 'Nudity or sexual content':
          return context.t.userReportReasonNudity;
        case 'Violence or threats':
          return context.t.userReportReasonViolence;
        default:
          return context.t.userReportReasonOther;
      }
    }

    final detailsCtrl = TextEditingController();
    String selectedReason = reasons.first;
    bool sending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.userReportProfile,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final reason in reasons)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: reason,
                        groupValue: selectedReason,
                        onChanged: sending
                            ? null
                            : (v) {
                                if (v == null) return;
                                setModalState(() => selectedReason = v);
                              },
                        title: Text(reasonLabel(reason)),
                      ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: detailsCtrl,
                      maxLines: 3,
                      maxLength: 2000,
                      enabled: !sending,
                      decoration: InputDecoration(
                        labelText: context.t.userReportDetailsOptional,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                sending ? null : () => Navigator.pop(ctx),
                            child: Text(context.t.cancel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: sending
                                ? null
                                : () async {
                                    setModalState(() => sending = true);
                                    try {
                                      await ref
                                          .read(userServiceProvider)
                                          .reportUserProfile(
                                            targetUid: targetUid,
                                            targetUsername: targetUsername,
                                            targetAvatar: targetAvatar,
                                            reason: selectedReason,
                                            details: detailsCtrl.text,
                                          );
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(context
                                                .t.postCardReportSentAdmins)),
                                      );
                                    } catch (e) {
                                      if (!ctx.mounted) return;
                                      setModalState(() => sending = false);
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text(e.toString())),
                                      );
                                    }
                                  },
                            child: Text(context.t.homeSendReport),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    // Defer disposal until after the sheet's widgets have fully unmounted;
    // disposing synchronously while the TextField is still tearing down its
    // listeners triggers the _dependents.isEmpty assertion in ChangeNotifier.
    WidgetsBinding.instance.addPostFrameCallback((_) => detailsCtrl.dispose());
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
            .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
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
                            context.t.profileNoUsersYet,
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
                                loading: () => Text(context.t.loading),
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
        error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
        data: (user) {
          if (user == null) {
            return SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.topStart,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(context.t.userNotFound),
                    ),
                  ),
                ],
              ),
            );
          }
          final username = (user['username'] as String?) ?? context.t.user;
          final displayName = (user['name'] as String?) ?? username;
          final handle = (user['handle'] as String?) ?? '@$username';
          final avatarUrl = user['avatarUrl'] as String?;
          final coverUrl = user['coverUrl'] as String?;
          final isPrivate = (user['isPrivate'] as bool?) ?? false;
          // Merge local overrides with stream values for instant feedback.
          final isFollowing =
              _localIsFollowing ?? (isFollowingAsync.value ?? false);
          final isRequested =
              _localIsRequested ?? (isRequestedAsync.value ?? false);
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
                  onReportTap: () => _reportProfile(
                    targetUid: widget.uid,
                    targetUsername: username,
                    targetAvatar: avatarUrl,
                  ),
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
                            SnackBar(content: Text(context.t.userUnblocked)),
                          );
                        }
                      } else {
                        await ref.read(blockServiceProvider).blockUser(
                              currentUid: currentUser.uid,
                              targetUid: widget.uid,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.t.userBlocked)),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text(context.t.userFailedBlockUnblock(e)),
                          ),
                        );
                      }
                    }
                  },
                  isBlocked: isBlocked,
                ),
                UserNameBio(
                  username: displayName,
                  handle: handle,
                  bio: (user['bio'] as String?) ?? '',
                  profession: (user['profession'] as String?) ?? '',
                  educationLevel: (user['academicLevel'] as String?) ?? '',
                  fieldOfStudy: (user['field'] as String?) ?? '',
                  isPrivate: isPrivate,
                ),
                if (!hideContent) ...[
                  UserStats(
                    followers: followers,
                    following: following,
                    posts: posts,
                    onFollowersTap: () => _showUserListSheet(
                      title: context.t.followers,
                      uids: followersAsync.value ?? const [],
                    ),
                    onFollowingTap: () => _showUserListSheet(
                      title: context.t.following,
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
                          : () => _toggleFollow(
                              isFollowing, isRequested, isPrivate),
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
                    else if (selectedTab == 1)
                      _UserQaActivitySection(uid: widget.uid)
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
                              ? context.t.userNotFound
                              : context.t.userYouBlockedThisUser,
                          style: TextStyle(
                              fontSize: 16, color: context.textSecondary),
                        ),
                        if (isBlocked && !isBlockedBy) ...[
                          const SizedBox(height: 6),
                          Text(
                            context.t.userBlockedContentHidden,
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
                              label: Text(context.t.unblock),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB05ECC),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
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
                                      SnackBar(
                                          content:
                                              Text(context.t.userUnblocked)),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            context.t.userFailedUnblock(e)),
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
        child: Center(child: Text(context.t.errorWithMessage(e))),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(context.t.noPosts,
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
        child: Center(child: Text(context.t.errorWithMessage(e))),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(context.t.profileNoRepostsYet,
                  style: TextStyle(color: context.textSecondary)),
            ),
          );
        }
        return _postsGrid(context, posts);
      },
    );
  }
}

class _UserQaActivitySection extends ConsumerStatefulWidget {
  final String uid;
  const _UserQaActivitySection({required this.uid});

  @override
  ConsumerState<_UserQaActivitySection> createState() =>
      _UserQaActivitySectionState();
}

class _UserQaActivitySectionState
    extends ConsumerState<_UserQaActivitySection> {
  int _innerTab = 0; // 0 asked, 1 answered

  @override
  Widget build(BuildContext context) {
    final askedAsync = ref.watch(userQaAskedProvider(widget.uid));
    final answeredAsync = ref.watch(userQaAnsweredProvider(widget.uid));

    Widget activityList(AsyncValue<List<Post>> asyncPosts,
        {required bool asked}) {
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
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  asked
                      ? context.t.profileNoQuestionsAsked
                      : context.t.profileNoAnswersYet,
                  style: TextStyle(color: context.textSecondary),
                ),
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                  child: _UserQaInnerTab(
                    label: context.t.profileQuestionsAsked,
                    selected: _innerTab == 0,
                    onTap: () => setState(() => _innerTab = 0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _UserQaInnerTab(
                    label: context.t.profileQuestionsAnswered,
                    selected: _innerTab == 1,
                    onTap: () => setState(() => _innerTab = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        _innerTab == 0
            ? activityList(askedAsync, asked: true)
            : activityList(answeredAsync, asked: false),
      ],
    );
  }
}

class _UserQaInnerTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UserQaInnerTab({
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
}
