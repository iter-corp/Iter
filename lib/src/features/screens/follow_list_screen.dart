import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/follow_providers.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/skeleton_loader.dart';

/// Which list a [_UserList] tab renders, and therefore which row action
/// (if any) it offers when the viewer owns the profile.
enum _FollowKind { followers, following }

/// Full-screen Followers / Following browser with two swipeable tabs, each
/// with its own search box. When the signed-in user is viewing their OWN
/// profile, rows expose an action: "Remove" on the Followers tab (drops that
/// user's follow of me) and "Unfollow" on the Following tab.
///
/// Replaces the old single-list bottom sheet. [initialTab] selects which tab
/// shows first (0 = Followers, 1 = Following) so tapping either count on the
/// profile lands on the matching list.
class FollowListScreen extends ConsumerWidget {
  final String uid;
  final int initialTab;

  const FollowListScreen({
    super.key,
    required this.uid,
    this.initialTab = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionUid = ref.watch(authStateProvider.select((a) => a.value?.uid)) ??
        ApiClient.instance.currentUserId;
    final isOwnProfile = sessionUid != null && sessionUid == uid;

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      // One AppPageBackground spanning the whole screen (the app bar is
      // see-through and extends the body behind it) so there's no seam
      // where a separate app-bar copy of the gradient would meet the body.
      // The app bar + tabs + each tab's search box are all fixed; only the
      // user list scrolls.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            tabs: [
              Tab(text: context.t.followers),
              Tab(text: context.t.following),
            ],
          ),
        ),
        body: AppPageBackground(
          child: Column(
            children: [
              SizedBox(
                height: kToolbarHeight +
                    kTextTabBarHeight +
                    MediaQuery.of(context).padding.top,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _UserList(
                      usersProvider: followersProvider(uid),
                      kind: _FollowKind.followers,
                      isOwnProfile: isOwnProfile,
                    ),
                    _UserList(
                      usersProvider: followingProvider(uid),
                      kind: _FollowKind.following,
                      isOwnProfile: isOwnProfile,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab's searchable list of users, driven by a follow provider that
/// streams the member uids. Each row streams the user's live doc for an
/// up-to-date avatar / username and opens that profile on tap.
class _UserList extends ConsumerStatefulWidget {
  final Refreshable<AsyncValue<List<String>>> usersProvider;
  final _FollowKind kind;
  final bool isOwnProfile;

  const _UserList({
    required this.usersProvider,
    required this.kind,
    required this.isOwnProfile,
  });

  @override
  ConsumerState<_UserList> createState() => _UserListState();
}

class _UserListState extends ConsumerState<_UserList> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(widget.usersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _buildSearchField(context),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final _ = ref.refresh(widget.usersProvider);
            },
            child: usersAsync.when(
              loading: () => const SkeletonUserList(),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  Center(
                    child: Text(
                      context.t.errorWithMessage(e.toString()),
                      style: TextStyle(color: context.textSecondary),
                    ),
                  ),
                ],
              ),
              data: (uids) {
                if (uids.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                      Center(
                        child: Text(
                          context.t.profileNoUsersYet,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                    ],
                  );
                }

                // Resolve every user's doc up front via the shared, cached
                // userByUidProvider so search can match ALL of them (not just
                // the rows currently scrolled into view). A row that hasn't
                // loaded yet is kept while the query is empty and only filtered
                // out once its name is known and doesn't match.
                final docs = <String, Map<String, dynamic>?>{
                  for (final uid in uids)
                    uid: ref.watch(userByUidProvider(uid)).valueOrNull,
                };

                bool matches(String uid) {
                  if (_query.isEmpty) return true;
                  final data = docs[uid];
                  if (data == null) return false; // unknown name can't match
                  final username =
                      (data['username'] as String?)?.toLowerCase() ?? '';
                  final handle = (data['handle'] as String?)?.toLowerCase() ?? '';
                  return username.contains(_query) || handle.contains(_query);
                }

                final visible = uids.where(matches).toList();

                if (visible.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                      Center(
                        child: Text(
                          context.t.followListNoMatches,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final uid = visible[index];
                    return _buildRow(context, uid, docs[uid]);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Search field styled to match the home screen's search input: white
  /// fill in light mode (inputFill in dark), 20px radius, neutral border
  /// that turns purple on focus, leading search icon.
  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? context.inputFill : Colors.white;
    final borderColor = isDark ? Colors.transparent : const Color(0xFFD5D7DF);

    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      style: TextStyle(color: context.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: context.t.followListSearchHint,
        hintStyle: TextStyle(color: context.textSecondary),
        filled: true,
        fillColor: fieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        prefixIcon: Icon(Icons.search, color: context.textSecondary),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: Icon(Icons.close, size: 18, color: context.textSecondary),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF7E3BE8), width: 1.2),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String uid,
    Map<String, dynamic>? data,
  ) {
    // Until the user doc has loaded, show a neutral placeholder row rather
    // than falling back to the raw uid — otherwise the Firestore document id
    // would flash before the real name arrives. The doc is resolved up in
    // build() via userByUidProvider and passed in here.
    if (data == null) return _placeholderRow(context);

    final avatarUrl = data['avatarUrl'] as String?;
    final username = (data['username'] as String?) ?? '';
    final handle = (data['handle'] as String?) ?? '';

    return ListTile(
      onTap: () => openUserProfile(context, uid: uid),
      leading: CircleAvatar(
        backgroundColor: context.inputFill,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null ? const Icon(Icons.person, size: 18) : null,
      ),
      title: Text(username),
      subtitle: Text(
        handle,
        style: TextStyle(color: context.textSecondary),
      ),
      trailing: widget.isOwnProfile
          ? _RowAction(
              kind: widget.kind,
              targetUid: uid,
              targetName: username,
            )
          : null,
    );
  }

  /// Skeleton shown while a row's user doc is still streaming in — a blank
  /// avatar and two grey bars, so no raw uid is ever visible.
  Widget _placeholderRow(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 12,
          decoration: BoxDecoration(
            color: context.inputFill,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.inputFill,
        child: Icon(Icons.person, size: 18, color: context.textSecondary),
      ),
      title:
          Align(alignment: AlignmentDirectional.centerStart, child: bar(140)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child:
            Align(alignment: AlignmentDirectional.centerStart, child: bar(90)),
      ),
    );
  }
}

/// The per-row action button shown only on the viewer's own profile:
/// "Unfollow" on the Following tab, "Remove" on the Followers tab. Both
/// confirm first, then call [FollowService.unfollow] in the right direction.
class _RowAction extends ConsumerStatefulWidget {
  final _FollowKind kind;
  final String targetUid;
  final String targetName;

  const _RowAction({
    required this.kind,
    required this.targetUid,
    required this.targetName,
  });

  @override
  ConsumerState<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends ConsumerState<_RowAction> {
  bool _busy = false;

  Future<void> _run() async {
    final sessionUid = ref.read(authStateProvider).value?.uid ??
        ApiClient.instance.currentUserId;
    if (sessionUid == null || _busy) return;

    final isUnfollow = widget.kind == _FollowKind.following;
    final message = isUnfollow
        ? context.t.followListUnfollowConfirm(widget.targetName)
        : context.t.followListRemoveFollowerConfirm(widget.targetName);
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg = context.t.userFollowActionFailed;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(dctx.t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(dctx.t.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final service = ref.read(followServiceProvider);
    try {
      if (isUnfollow) {
        // I stop following them.
        await service.unfollow(
          currentUid: sessionUid,
          targetUid: widget.targetUid,
        );
      } else {
        // Remove a follower = make them stop following me.
        await service.unfollow(
          currentUid: widget.targetUid,
          targetUid: sessionUid,
        );
      }
      // The follow provider streams the change, so the row drops out on its
      // own — no local list mutation needed.
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failedMsg(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.kind == _FollowKind.following
        ? context.t.unfollow
        : context.t.followListRemoveFollower;

    // Same gradient pill as the home "Post" button.
    return PrimaryActionButton(
      label: label,
      onPressed: _busy ? null : _run,
      loading: _busy,
    );
  }
}
