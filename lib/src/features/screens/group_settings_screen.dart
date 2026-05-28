import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../theme/app_theme.dart';

/// Group chat settings screen — shows the member list (with the admin
/// badge for the user who created the group), gives non-admins a "Leave
/// group" action, and exposes the existing permission toggles to admins.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String groupName;

  const GroupSettingsScreen({
    super.key,
    required this.chatId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.groupSettingsDeleteGroupTitle),
        content: Text(
          context.t.groupSettingsDeleteGroupBody(widget.groupName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.t.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(chatServiceProvider).deleteGroup(widget.chatId);
      if (!mounted) return;
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.groupSettingsFailedToDelete(e))));
    }
  }

  bool _isSaving = false;

  Future<void> _savePermissions({
    required bool restrictMessaging,
    required bool adminOnly,
    required bool mediaShare,
  }) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'restrictMessaging': restrictMessaging,
        'adminOnly': adminOnly,
        'mediaShare': mediaShare,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.groupSettingsSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.groupSettingsError(e))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _leaveGroup() async {
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.groupSettingsLeaveGroupTitle),
        content: Text(
          context.t.groupSettingsLeaveGroupBody(widget.groupName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.t.groupSettingsLeaveGroup,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(chatServiceProvider).leaveOrRemoveGroupMember(
            chatId: widget.chatId,
            uid: currentUid,
          );
      if (!mounted) return;
      // Pop the settings screen and the underlying chat screen so we
      // don't leave the user stranded in a group they're no longer in.
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.groupSettingsFailedToLeave(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final chatDocAsync = ref.watch(chatDocProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        centerTitle: false,
      ),
      body: chatDocAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.t.groupSettingsError(e))),
        data: (data) {
          if (data == null) {
            return Center(child: Text(context.t.groupSettingsGroupNotFound));
          }
          final participants =
              List<String>.from(data['participants'] as List? ?? []);
          final adminUid = (data['adminUid'] as String?) ?? '';
          final userData =
              (data['userData'] as Map<String, dynamic>?) ?? const {};
          final isAdmin = currentUid != null && currentUid == adminUid;
          final restrictMessaging =
              (data['restrictMessaging'] as bool?) ?? false;
          final adminOnly = (data['adminOnly'] as bool?) ?? false;
          final mediaShare = (data['mediaShare'] as bool?) ?? true;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _MembersHeader(count: participants.length),
              for (final uid in _sortMembers(participants, adminUid))
                _MemberTile(
                  uid: uid,
                  cachedData:
                      (userData[uid] as Map<String, dynamic>?) ?? const {},
                  isAdmin: uid == adminUid,
                  isMe: uid == currentUid,
                ),
              const SizedBox(height: 8),
              if (currentUid != null && !isAdmin)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _leaveGroup,
                    icon: const Icon(Icons.logout),
                    label: Text(context.t.groupSettingsLeaveGroup),
                  ),
                ),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                _PermissionsSection(
                  restrictMessaging: restrictMessaging,
                  adminOnly: adminOnly,
                  mediaShare: mediaShare,
                  saving: _isSaving,
                  onSave: _savePermissions,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _deleteGroup,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.t.groupSettingsDeleteGroup),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// Admin first, then everyone else in the original order. Keeps the
  /// "creator" visually anchored at the top of the list.
  List<String> _sortMembers(List<String> uids, String adminUid) {
    if (adminUid.isEmpty) return uids;
    final out = <String>[
      if (uids.contains(adminUid)) adminUid,
      ...uids.where((u) => u != adminUid),
    ];
    return out;
  }
}

class _MembersHeader extends StatelessWidget {
  final int count;
  const _MembersHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(Icons.groups, size: 20, color: context.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$count ${count == 1 ? context.t.groupSettingsMember : context.t.groupSettingsMembers}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  final String uid;
  final Map<String, dynamic> cachedData;
  final bool isAdmin;
  final bool isMe;

  const _MemberTile({
    required this.uid,
    required this.cachedData,
    required this.isAdmin,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAsync = ref.watch(userByUidProvider(uid));
    final live = liveAsync.value;
    final username = (live?['username'] as String?) ??
        (cachedData['username'] as String?) ??
        '';
    final avatarUrl = (live?['avatarUrl'] as String?) ??
        (cachedData['avatarUrl'] as String?) ??
        '';

    return ListTile(
      onTap: () => openUserProfile(context, uid: uid),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: context.inputFill,
        backgroundImage:
            avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? Icon(Icons.person, color: context.textSecondary)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              username.isEmpty ? context.t.groupSettingsUserFallback : username,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            Text(
              context.t.groupSettingsYouSuffix,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.purpleSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield,
                    size: 12,
                    color: Color(0xFFB05ECC),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.t.groupSettingsAdmin,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB05ECC),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _PermissionsSection extends StatefulWidget {
  final bool restrictMessaging;
  final bool adminOnly;
  final bool mediaShare;
  final bool saving;
  final Future<void> Function({
    required bool restrictMessaging,
    required bool adminOnly,
    required bool mediaShare,
  }) onSave;

  const _PermissionsSection({
    required this.restrictMessaging,
    required this.adminOnly,
    required this.mediaShare,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<_PermissionsSection> {
  late bool _restrict;
  late bool _adminOnly;
  late bool _media;

  @override
  void initState() {
    super.initState();
    _restrict = widget.restrictMessaging;
    _adminOnly = widget.adminOnly;
    _media = widget.mediaShare;
  }

  @override
  void didUpdateWidget(covariant _PermissionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local toggle state in sync with the live chat doc, except
    // while a save is in flight (so an in-progress edit isn't snapped
    // back to its previous value).
    if (!widget.saving) {
      _restrict = widget.restrictMessaging;
      _adminOnly = widget.adminOnly;
      _media = widget.mediaShare;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.groupSettingsMessagingPermissions,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.lock_outline,
            title: context.t.groupSettingsRestrictMessaging,
            subtitle: context.t.groupSettingsRestrictMessagingDesc,
            value: _restrict,
            onChanged: (v) => setState(() {
              _restrict = v;
              if (v) _adminOnly = false;
            }),
          ),
          const SizedBox(height: 10),
          _PermissionCard(
            icon: Icons.admin_panel_settings_outlined,
            title: context.t.groupSettingsAdminOnlyMode,
            subtitle: context.t.groupSettingsAdminOnlyModeDesc,
            value: _adminOnly,
            onChanged: (v) => setState(() {
              _adminOnly = v;
              if (v) _restrict = false;
            }),
          ),
          const SizedBox(height: 10),
          _PermissionCard(
            icon: Icons.image_outlined,
            title: context.t.groupSettingsEnableMediaSharing,
            subtitle: context.t.groupSettingsEnableMediaSharingDesc,
            value: _media,
            onChanged: (v) => setState(() => _media = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.saving
                  ? null
                  : () => widget.onSave(
                        restrictMessaging: _restrict,
                        adminOnly: _adminOnly,
                        mediaShare: _media,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB05ECC),
                padding: const EdgeInsets.symmetric(vertical: 12),
                disabledBackgroundColor: Colors.grey.shade400,
              ),
              child: widget.saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      context.t.groupSettingsSaveSettings,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFFB05ECC) : Colors.transparent,
          width: value ? 2 : 0,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB05ECC), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFB05ECC),
            activeTrackColor: const Color(0xFFB05ECC).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
