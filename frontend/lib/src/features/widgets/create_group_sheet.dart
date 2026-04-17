import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/follow_providers.dart';
import '../screens/chat_screen.dart';

/// Opens a bottom sheet that lets the signed-in user create a new group chat
/// by picking members from the accounts they follow.
Future<void> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
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
  final Set<String> _selected = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
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
          SnackBar(content: Text('Failed: $e')),
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
        return Padding(
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'New group',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Group name',
                    filled: true,
                    fillColor: const Color(0xFFF0F0F0),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add members (from people you follow)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: followingAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (uids) {
                    if (uids.isEmpty) {
                      return const Center(
                        child: Text(
                          'You aren\'t following anyone yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: uids.length,
                      itemBuilder: (_, i) => _UserRow(
                        uid: uids[i],
                        selected: _selected.contains(uids[i]),
                        onToggle: (v) => setState(() {
                          if (v) {
                            _selected.add(uids[i]);
                          } else {
                            _selected.remove(uids[i]);
                          }
                        }),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ||
                              _selected.isEmpty ||
                              _nameCtrl.text.trim().isEmpty
                          ? null
                          : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB05ECC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Create'
                              '${_selected.isEmpty ? '' : ' (${_selected.length})'}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserRow extends ConsumerWidget {
  final String uid;
  final bool selected;
  final ValueChanged<bool> onToggle;

  const _UserRow({
    required this.uid,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final username = (d['username'] as String?) ?? uid;
        final avatar = (d['avatarUrl'] as String?) ?? '';
        return CheckboxListTile(
          value: selected,
          onChanged: (v) => onToggle(v ?? false),
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade200,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          title: Text(username,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          activeColor: const Color(0xFFB05ECC),
        );
      },
    );
  }
}
