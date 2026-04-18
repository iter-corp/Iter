import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';

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
        title: const Text('Users'),
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
                hintText: 'Search by username or email',
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
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (users) {
                if (users.isEmpty) {
                  return Center(
                      child: Text('No users match',
                          style: TextStyle(color: context.textSecondary)));
                }
                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _UserTile(user: users[i]),
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

    return ListTile(
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
          if (role == 'admin')
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.purpleSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('ADMIN',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD044E8))),
            ),
          if (suspended)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('SUSPENDED',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
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
            child:
                Text(role == 'admin' ? 'Demote to user' : 'Promote to admin'),
          ),
          PopupMenuItem(
            value: 'suspend',
            child: Text(suspended ? 'Unsuspend' : 'Suspend'),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete user', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String uid,
      String action, String role, bool suspended) async {
    final admin = ref.read(adminServiceProvider);
    try {
      if (action == 'role') {
        await admin.setRole(uid, role == 'admin' ? 'user' : 'admin');
      } else if (action == 'suspend') {
        await admin.suspendUser(uid, !suspended);
      } else if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete user permanently?'),
            content: const Text(
                'This will delete ALL user data: posts, comments, stories, chats, followers, and notifications. Their email will be blacklisted.\n\nThis cannot be undone.'),
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
        if (ok == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deleting all user data...')),
            );
          }
          await admin.deleteUser(uid);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User deleted and blacklisted')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
