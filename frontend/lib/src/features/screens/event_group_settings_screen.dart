import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../providers/event_registration_providers.dart';
import '../../providers/follow_providers.dart';
import '../../services/event_registration_service.dart';
import '../../theme/app_theme.dart';

/// Settings page for an event group chat. For the event's admin, this shows
/// pending registrations (to approve/reject), current members (with remove
/// buttons), and an "Add user" button. For regular members, it's a read-only
/// member list with a "Leave group" action.
class EventGroupSettingsScreen extends ConsumerWidget {
  final String eventId;
  final String eventTitle;
  final String adminUid;

  const EventGroupSettingsScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.adminUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final isAdmin = currentUid != null && currentUid == adminUid;

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('Group settings'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(title: eventTitle),
          if (isAdmin) ...[
            const _SectionTitle(title: 'Pending requests'),
            _PendingList(eventId: eventId),
            _SectionTitle(
              title: 'Members',
              action: TextButton.icon(
                onPressed: () => _openAddUserSheet(context, ref),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add user'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB05ECC),
                ),
              ),
            ),
            _MemberList(eventId: eventId, adminUid: adminUid, isAdmin: true),
          ] else ...[
            const _SectionTitle(title: 'Members'),
            _MemberList(eventId: eventId, adminUid: adminUid, isAdmin: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLeave(context, ref),
                icon: const Icon(Icons.logout, color: Color(0xFFE04E5C)),
                label: const Text(
                  'Leave group',
                  style: TextStyle(color: Color(0xFFE04E5C)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE04E5C)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddUserSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddUserSheet(eventId: eventId),
    );
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
            'You\'ll stop receiving messages for this event. You can re-register later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave',
                  style: TextStyle(color: Color(0xFFE04E5C)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(eventChatServiceProvider).leaveGroup(eventId);
      if (context.mounted) {
        Navigator.pop(context); // pop settings
        Navigator.pop(context); // pop chat
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFB05ECC),
            child: Icon(Icons.groups, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Event group chat',
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionTitle({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Pending registrations (admin only)
// ─────────────────────────────────────────────

class _PendingList extends ConsumerWidget {
  final String eventId;
  const _PendingList({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(eventRegistrationServiceProvider);
    return StreamBuilder<List<EventRegistration>>(
      stream: svc.streamPendingForEvent(eventId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data ?? const <EventRegistration>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No pending requests',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          );
        }
        return Column(
          children: [
            for (final r in items)
              _PendingCard(reg: r),
          ],
        );
      },
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  final EventRegistration reg;
  const _PendingCard({required this.reg});

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reg;
    final svc = ref.read(eventRegistrationServiceProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(r.email,
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
          if (r.phone.isNotEmpty)
            Text('${r.countryCode} ${r.phone}',
                style: TextStyle(
                    fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(() => svc.reject(r)),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE04E5C),
                    side: const BorderSide(color: Color(0xFFE04E5C)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _run(() => svc.approve(r)),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EBD6B),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Members list
// ─────────────────────────────────────────────

class _MemberList extends ConsumerWidget {
  final String eventId;
  final String adminUid;
  final bool isAdmin;

  const _MemberList({
    required this.eventId,
    required this.adminUid,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(eventChatMembersProvider(eventId));
    return membersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load members: $e',
            style: TextStyle(color: context.textSecondary)),
      ),
      data: (members) {
        if (members.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No members yet',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          );
        }
        return Column(
          children: [
            for (final m in members)
              _MemberRow(
                eventId: eventId,
                uid: (m['uid'] as String?) ?? (m['id'] as String? ?? ''),
                adminUid: adminUid,
                isAdminViewer: isAdmin,
              ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String eventId;
  final String uid;
  final String adminUid;
  final bool isAdminViewer;

  const _MemberRow({
    required this.eventId,
    required this.uid,
    required this.adminUid,
    required this.isAdminViewer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isEmpty) return const SizedBox.shrink();
    final live = ref.watch(userByUidProvider(uid)).value;
    final username = (live?['username'] as String?) ?? 'Member';
    final avatar = (live?['avatarUrl'] as String?) ?? '';
    final isTheAdmin = uid == adminUid;

    return ListTile(
      onTap: () => openUserProfile(context, uid: uid),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: context.inputFill,
        backgroundImage:
            avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
        child: avatar.isEmpty
            ? Icon(Icons.person, color: context.textSecondary)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(username,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (isTheAdmin) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.purpleSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFFB05ECC),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: isAdminViewer && !isTheAdmin
          ? IconButton(
              icon: const Icon(Icons.person_remove_outlined,
                  color: Colors.red),
              onPressed: () => _confirmRemove(context, ref, username),
            )
          : null,
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
            'They\'ll stop receiving messages and will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(eventChatServiceProvider)
          .removeMember(eventId: eventId, uid: uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ─────────────────────────────────────────────
// Add-user sheet (admin) — picks from followed accounts.
// ─────────────────────────────────────────────

class _AddUserSheet extends ConsumerStatefulWidget {
  final String eventId;
  const _AddUserSheet({required this.eventId});

  @override
  ConsumerState<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends ConsumerState<_AddUserSheet> {
  bool _busy = false;

  Future<void> _add(String uid, String username) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventChatServiceProvider).addMember(
            eventId: widget.eventId,
            uid: uid,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $username to the group')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).value?.uid;
    final followingAsync = me == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followingProvider(me));
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add user to group',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: followingAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (uids) {
                  if (uids.isEmpty) {
                    return Center(
                      child: Text(
                        'You aren\'t following anyone yet.',
                        style: TextStyle(color: context.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: uids.length,
                    itemBuilder: (_, i) => _FollowedUserRow(
                      uid: uids[i],
                      busy: _busy,
                      onAdd: (name) => _add(uids[i], name),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FollowedUserRow extends StatelessWidget {
  final String uid;
  final bool busy;
  final void Function(String username) onAdd;

  const _FollowedUserRow({
    required this.uid,
    required this.busy,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final username = (d['username'] as String?) ?? uid;
        final avatar = (d['avatarUrl'] as String?) ?? '';
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: context.inputFill,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Icon(Icons.person, color: context.textSecondary)
                : null,
          ),
          title: Text(username,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: ElevatedButton(
            onPressed: busy ? null : () => onAdd(username),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB05ECC),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Add'),
          ),
        );
      },
    );
  }
}
