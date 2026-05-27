import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/follow_providers.dart';
import '../../theme/app_theme.dart';
import '../screens/chat_screen.dart';
import 'app_page_background.dart';
import 'primary_action_button.dart';

/// Opens a bottom sheet that lets the signed-in user create a new group chat
/// by picking members from the accounts they follow.
Future<void> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CreateGroupSheet(),
  );
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selected = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final me = ref.read(authStateProvider).value?.uid;
    if (me == null) return;
    if (_selected.isEmpty) return;
    if (_nameCtrl.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final id = await ref.read(chatServiceProvider).createGroup(
            creatorUid: me,
            memberUids: _selected.toList(),
            groupName: _nameCtrl.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: id,
            otherUid: '',
            otherName: _nameCtrl.text.trim(),
            otherAvatar: '',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.createGroupFailed(e))),
        );
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
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: AppPageBackground(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.t.createGroupNewGroup,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _GlassInput(
                  controller: _nameCtrl,
                  hintText: context.t.createGroupGroupName,
                  icon: Icons.group_outlined,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _GlassInput(
                  controller: _searchCtrl,
                  hintText: context.t.createGroupSearchPeople,
                  icon: Icons.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.t.createGroupAddMembers,
                    style:
                        TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: followingAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text(context.t.createGroupError(e))),
                  data: (uids) {
                    if (uids.isEmpty) {
                      return Center(
                        child: Text(
                          context.t.createGroupNotFollowingAnyone,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: uids.length,
                      itemBuilder: (_, i) => _UserRow(
                        uid: uids[i],
                        selected: _selected.contains(uids[i]),
                        query: _query,
                        onToggle: (v) => setState(() {
                          if (v) {
                            _selected.add(uids[i]);
                          } else {
                            _selected.remove(uids[i]);
                          }
                        }),
                        currentUid: me ?? '',
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PrimaryActionButton(
                    label: _selected.isEmpty
                        ? context.t.createGroupCreate
                        : context.t.createGroupCreateCount(_selected.length),
                    onPressed: _busy ||
                            _selected.isEmpty ||
                            _nameCtrl.text.trim().isEmpty
                        ? null
                        : _submit,
                    loading: _busy,
                    size: PrimaryActionSize.large,
                    fullWidth: true,
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  const _GlassInput({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      radius: 16,
      surfaceAlpha: context.isDark ? 0.42 : 0.36,
      borderAlpha: context.isDark ? 0.14 : 0.50,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: context.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: context.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.purple),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  final String uid;
  final bool selected;
  final String query;
  final ValueChanged<bool> onToggle;
  final String currentUid;

  const _UserRow({
    required this.uid,
    required this.selected,
    required this.query,
    required this.onToggle,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBlockedAsync = ref.watch(isBlockedProvider(uid));
    final isBlockedByAsync = ref.watch(isBlockedByProvider(uid));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final username = (d['username'] as String?) ?? uid;
        final fullName = (d['fullName'] as String?) ?? '';
        final avatar = (d['avatarUrl'] as String?) ?? '';

        final isBlocked = isBlockedAsync.value ?? false;
        final isBlockedBy = isBlockedByAsync.value ?? false;

        // Hide blocked users from the list
        if (isBlocked || isBlockedBy) {
          return const SizedBox.shrink();
        }

        final q = query.trim().toLowerCase();
        if (q.isNotEmpty &&
            !username.toLowerCase().contains(q) &&
            !fullName.toLowerCase().contains(q)) {
          return const SizedBox.shrink();
        }

        return AppGlassCard(
          margin: const EdgeInsets.symmetric(vertical: 4),
          radius: 16,
          surfaceAlpha: context.isDark ? 0.42 : 0.36,
          borderAlpha: selected ? 0.65 : (context.isDark ? 0.14 : 0.50),
          emphasize: selected,
          child: CheckboxListTile(
            value: selected,
            onChanged: (v) => onToggle(v ?? false),
            controlAffinity: ListTileControlAffinity.trailing,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            checkboxShape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            secondary: CircleAvatar(
              radius: 20,
              backgroundColor: context.inputFill,
              backgroundImage:
                  avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
              child: avatar.isEmpty
                  ? Icon(Icons.person, color: context.textSecondary)
                  : null,
            ),
            title: Text(
              username,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            subtitle: fullName.trim().isEmpty
                ? null
                : Text(
                    fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textSecondary),
                  ),
            activeColor: AppColors.purple,
          ),
        );
      },
    );
  }
}
