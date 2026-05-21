import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';
import '../user_screen.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider(_query));
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(context.t.adminTileUsersTitle),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.t.adminUsersSearchHint,
                filled: true,
                fillColor: context.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
              data: (users) {
                if (users.isEmpty) {
                  return Center(
                      child: Text(context.t.adminNoUsersMatch,
                          style: TextStyle(color: context.textSecondary)));
                }
                final sorted = [...users]..sort((a, b) {
                    final aRole = (a['role'] as String? ?? 'user');
                    final bRole = (b['role'] as String? ?? 'user');
                    if (aRole == bRole) {
                      final aName = (a['username'] as String? ??
                              a['email'] as String? ??
                              '')
                          .toLowerCase();
                      final bName = (b['username'] as String? ??
                              b['email'] as String? ??
                              '')
                          .toLowerCase();
                      return aName.compareTo(bName);
                    }
                    if (aRole == 'admin') return -1;
                    if (bRole == 'admin') return 1;
                    if (aRole == 'org_admin') return -1;
                    if (bRole == 'org_admin') return 1;
                    return 0;
                  });
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _UserTile(user: sorted[i]),
                  ),
                );
              },
            ),
          ),
        ],
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
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final avatar = user['avatarUrl'] as String?;
    final role = user['role'] as String? ?? 'user';
    final suspended = (user['suspended'] as bool?) ?? false;
    final isAdmin = role == 'admin';
    final isOrgAdmin = role == 'org_admin';

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
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
                username.isEmpty ? email : username,
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
                label: 'EVENT MANAGER',
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
        subtitle: Text(email,
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
                    ? 'Revoke event manager'
                    : 'Grant event manager'),
              ),
            PopupMenuItem(
              value: 'suspend',
              child: Text(
                  suspended ? context.t.adminUnsuspend : context.t.adminSuspend),
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
          builder: (_) => AlertDialog(
            title: Text(isRevoking
                ? 'Revoke event manager access?'
                : 'Grant event manager access?'),
            content: Text(isRevoking
                ? 'This will remove event posting permissions and set role to user.'
                : 'This will grant event posting permissions by making this user an event manager.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isRevoking ? 'Revoke' : 'Grant'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await admin.setRole(uid, isRevoking ? 'user' : 'org_admin');
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
      }
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
