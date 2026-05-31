import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';
import '../user_screen.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';

  /// Partition users into the tab buckets. We compute these once per build
  /// so each tab gets its filtered list without re-walking the source.
  ({
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> admins,
    List<Map<String, dynamic>> eventManagers,
    List<Map<String, dynamic>> regular,
    List<Map<String, dynamic>> suspended,
  }) _bucket(List<Map<String, dynamic>> users) {
    final admins = <Map<String, dynamic>>[];
    final eventManagers = <Map<String, dynamic>>[];
    final regular = <Map<String, dynamic>>[];
    final suspended = <Map<String, dynamic>>[];
    for (final u in users) {
      final role = u['role'] as String? ?? 'user';
      // Suspended users get their own bucket regardless of role so they
      // surface in one place; the admin can still see them in the All tab.
      if ((u['suspended'] as bool?) ?? false) {
        suspended.add(u);
      }
      if (role == 'admin') {
        admins.add(u);
      } else if (role == 'org_admin') {
        eventManagers.add(u);
      } else {
        regular.add(u);
      }
    }
    return (
      all: users,
      admins: admins,
      eventManagers: eventManagers,
      regular: regular,
      suspended: suspended,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pass the query down to the server-side provider so the filter applies
    // across all tabs. The buckets below then slice the already-filtered
    // list by role/suspended state.
    final usersAsync = ref.watch(adminUsersProvider(_query));
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.t.adminTileUsersTitle),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        ),
        body: AppPageBackground(
          child: Column(
            children: [
              // One shared search field above the tabs so the query persists
              // and applies to whichever tab is active.
              Padding(
                padding: const EdgeInsets.all(12),
                child: AppGlassCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: false,
                        fillColor: Colors.transparent,
                      ),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        hintText: context.t.adminUsersSearchHint,
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: usersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text(context.t.errorWithMessage(e))),
                  data: (users) {
                    final b = _bucket(users);
                    return Column(
                      children: [
                        // Scrollable so longer translated labels (Arabic /
                        // Kurdish) don't crowd or clip on small screens.
                        Material(
                          color: Colors.transparent,
                          child: TabBar(
                            isScrollable: true,
                            labelColor: AppColors.purple,
                            unselectedLabelColor: context.textSecondary,
                            indicatorColor: AppColors.purple,
                            dividerColor: Colors.transparent,
                            dividerHeight: 0,
                            tabs: [
                              Tab(
                                  text:
                                      context.t.adminUsersTabAll(b.all.length)),
                              Tab(
                                  text: context.t
                                      .adminUsersTabAdmins(b.admins.length)),
                              Tab(
                                  text: context.t.adminUsersTabEventManagers(
                                      b.eventManagers.length)),
                              Tab(
                                  text: context.t
                                      .adminUsersTabRegular(b.regular.length)),
                              Tab(
                                  text: context.t.adminUsersTabSuspended(
                                      b.suspended.length)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _UsersList(users: b.all),
                              _UsersList(users: b.admins),
                              _UsersList(users: b.eventManagers),
                              _UsersList(users: b.regular),
                              _UsersList(users: b.suspended),
                            ],
                          ),
                        ),
                      ],
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
}

/// Renders one tab's worth of users. Sorts admins → event managers →
/// users so the All tab keeps the previous "role first, then name"
/// ordering even after the bucket split.
class _UsersList extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  const _UsersList({required this.users});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Center(
        child: Text(context.t.adminNoUsersMatch,
            style: TextStyle(color: context.textSecondary)),
      );
    }
    final sorted = [...users]..sort((a, b) {
        final aRole = (a['role'] as String? ?? 'user');
        final bRole = (b['role'] as String? ?? 'user');
        if (aRole == bRole) {
          final aName =
              (a['username'] as String? ?? a['email'] as String? ?? '')
                  .toLowerCase();
          final bName =
              (b['username'] as String? ?? b['email'] as String? ?? '')
                  .toLowerCase();
          return aName.compareTo(bName);
        }
        if (aRole == 'admin') return -1;
        if (bRole == 'admin') return 1;
        if (aRole == 'org_admin') return -1;
        if (bRole == 'org_admin') return 1;
        return 0;
      });
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 28;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      itemCount: sorted.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _UserTile(user: sorted[i]),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final Map<String, dynamic> user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = user['uid'] as String? ?? '';
    final username = (user['username'] as String? ?? '').trim();
    final email = (user['email'] as String? ?? '').trim();
    final avatar = user['avatarUrl'] as String?;
    final role = user['role'] as String? ?? 'user';
    final suspended = (user['suspended'] as bool?) ?? false;
    final isAdmin = role == 'admin';
    final isOrgAdmin = role == 'org_admin';

    // Title prefers username, then email, then the uid so the row never
    // renders blank. Subtitle then shows the email — but if we already
    // promoted the email up to the title (because no username was set)
    // we'd otherwise duplicate it on every row. Show "no email" in that
    // case so the admin can tell the difference between a user whose
    // email simply isn't on file (Apple hide-my-email, legacy docs,
    // anonymous sign-in) and the duplicate-display bug.
    final String title;
    final String subtitle;
    if (username.isNotEmpty) {
      title = username;
      subtitle = email.isEmpty ? context.t.adminUsersNoEmail : email;
    } else if (email.isNotEmpty) {
      title = email;
      subtitle = context.t.adminUsersNoEmail;
    } else {
      title = uid.isEmpty ? '—' : uid;
      subtitle = context.t.adminUsersNoEmail;
    }

    return AppGlassCard(
      radius: 16,
      child: ListTile(
        onTap: uid.isEmpty
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(uid: uid),
                  ),
                );
              },
        leading: CircleAvatar(
          backgroundColor: context.inputFill,
          backgroundImage: (avatar != null && avatar.isNotEmpty)
              ? CachedNetworkImageProvider(avatar)
              : null,
          child: (avatar == null || avatar.isEmpty)
              ? const Icon(Icons.person)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAdmin)
              _RoleChip(
                label: context.t.adminBadge,
                background: context.purpleSoft,
                foreground: const Color(0xFFD044E8),
              ),
            if (isOrgAdmin)
              _RoleChip(
                label: context.t.adminUsersEventManagerBadge,
                background: Colors.blue.shade50,
                foreground: Colors.blue.shade700,
              ),
            if (suspended)
              _RoleChip(
                label: context.t.adminSuspendedBadge,
                background: Colors.red.shade50,
                foreground: Colors.red,
              ),
          ],
        ),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.textSecondary, fontSize: 12)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) =>
              _handleAction(context, ref, uid, action, role, suspended),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'role',
              child: Text(isAdmin
                  ? context.t.adminDemoteToUser
                  : context.t.adminPromoteToAdmin),
            ),
            if (!isAdmin)
              PopupMenuItem(
                value: 'orgRole',
                child: Text(isOrgAdmin
                    ? context.t.adminUsersRevokeEventManager
                    : context.t.adminUsersGrantEventManager),
              ),
            PopupMenuItem(
              value: 'suspend',
              child: Text(suspended
                  ? context.t.adminUnsuspend
                  : context.t.adminSuspend),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(context.t.adminDeleteUser,
                  style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String uid,
      String action, String role, bool suspended) async {
    final admin = ref.read(adminServiceProvider);
    try {
      if (action == 'role') {
        await admin.setRole(uid, role == 'admin' ? 'user' : 'admin');
      } else if (action == 'orgRole') {
        final isRevoking = role == 'org_admin';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isRevoking
                ? ctx.t.adminUsersRevokeEventManagerTitle
                : ctx.t.adminUsersGrantEventManagerTitle),
            content: Text(isRevoking
                ? ctx.t.adminUsersRevokeEventManagerBody
                : ctx.t.adminUsersGrantEventManagerBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isRevoking
                    ? ctx.t.adminUsersRevoke
                    : ctx.t.adminUsersGrant),
              ),
            ],
          ),
        );
        if (ok == true) {
          await admin.setRole(uid, isRevoking ? 'user' : 'org_admin');
          // After revoking, offer to also delete every event the
          // (now demoted) user created. Two confirmations: the first
          // asks whether to delete, the second confirms the
          // irreversible action — declining the second returns to the
          // first so the admin can reconsider without re-revoking.
          if (isRevoking && context.mounted) {
            await _promptDeleteUserEvents(context, ref, uid);
          }
        }
      } else if (action == 'suspend') {
        await admin.suspendUser(uid, !suspended);
      } else if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(context.t.adminDeleteUserPermanentlyTitle),
            content: Text(context.t.adminDeleteUserPermanentlyBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t.cancel)),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t.adminDeleteEverything,
                      style: const TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (ok == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.adminDeletingAllUserData)),
            );
          }
          await admin.deleteUser(uid);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.adminUserDeletedBlacklisted)),
            );
          }
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[admin] action=$action failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.failedWithError(e))));
      }
    }
  }

  /// Two-step prompt offered right after revoking a user's event-manager
  /// role: "delete all their events?" → "are you sure?". Declining the
  /// second step loops back to the first so the admin can change their
  /// mind. Does nothing (silently) when the user has no events.
  Future<void> _promptDeleteUserEvents(
      BuildContext context, WidgetRef ref, String uid) async {
    final admin = ref.read(adminServiceProvider);
    final count = await admin.countEventsCreatedBy(uid);
    if (count == 0 || !context.mounted) return;

    while (true) {
      final wantsDelete = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.t.adminRevokeDeleteEventsTitle),
          content: Text(ctx.t.adminRevokeDeleteEventsBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t.adminRevokeKeepEvents),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                ctx.t.adminRevokeDeleteEventsYes,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
      if (wantsDelete != true || !context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.t.adminRevokeDeleteEventsConfirmTitle),
          content: Text(ctx.t.adminRevokeDeleteEventsConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.t.adminRevokeDeleteEventsYes),
            ),
          ],
        ),
      );

      // Confirmed → delete and stop. Declined → loop back to the first
      // prompt so the admin can choose "keep events" instead.
      if (confirmed == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.adminDeletingAllUserData)),
          );
        }
        await admin.deleteEventsCreatedBy(uid);
        return;
      }
      if (!context.mounted) return;
    }
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _RoleChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}
