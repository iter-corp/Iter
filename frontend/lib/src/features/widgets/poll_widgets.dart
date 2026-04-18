import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/poll_providers.dart';
import '../../services/poll_service.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet to create a new poll. Caller supplies [parentPath] — either
/// "chats/{id}" or "eventChats/{id}".
Future<void> showCreatePollSheet(
  BuildContext context, {
  required String parentPath,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CreatePollSheet(parentPath: parentPath),
  );
}

class _CreatePollSheet extends ConsumerStatefulWidget {
  final String parentPath;
  const _CreatePollSheet({required this.parentPath});

  @override
  ConsumerState<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<_CreatePollSheet> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  PollVisibility _visibility = PollVisibility.public;
  bool _busy = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= 10) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls.removeAt(i).dispose();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(pollServiceProvider).createPoll(
            parentPath: widget.parentPath,
            question: _questionCtrl.text,
            options: _optionCtrls.map((c) => c.text).toList(),
            visibility: _visibility,
          );
      if (mounted) Navigator.pop(context);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Create poll',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _questionCtrl,
                decoration: _decoration('Ask a question...'),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _optionCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionCtrls[i],
                          decoration: _decoration('Option ${i + 1}'),
                        ),
                      ),
                      if (_optionCtrls.length > 2)
                        IconButton(
                          onPressed: () => _removeOption(i),
                          icon: const Icon(Icons.close, size: 20),
                          color: Colors.grey,
                        ),
                    ],
                  ),
                ),
              if (_optionCtrls.length < 10)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              const SizedBox(height: 8),
              const Text('Visibility',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _VisibilityChip(
                      label: 'Public',
                      description: 'Voters visible',
                      icon: Icons.public,
                      active: _visibility == PollVisibility.public,
                      onTap: () => setState(
                          () => _visibility = PollVisibility.public),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VisibilityChip(
                      label: 'Secret',
                      description: 'Only counts visible',
                      icon: Icons.lock_outline,
                      active: _visibility == PollVisibility.secret,
                      onTap: () => setState(
                          () => _visibility = PollVisibility.secret),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
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
                      : const Text('Post poll',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

class _VisibilityChip extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _VisibilityChip({
    required this.label,
    required this.description,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              active ? context.purpleSoft : context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? const Color(0xFFB05ECC)
                : context.borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 18,
                color: active
                    ? const Color(0xFFB05ECC)
                    : Colors.grey.shade600),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(description,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// List of polls for a chat + inline voting UI.
class PollsSection extends ConsumerWidget {
  final String parentPath;

  /// When true, the current user may create polls. Event chats pass
  /// `canCreate: isAdmin`; 1:1 chats pass `canCreate: true`.
  final bool canCreate;

  const PollsSection({
    super.key,
    required this.parentPath,
    required this.canCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollsAsync = ref.watch(pollsProvider(parentPath));
    final polls = pollsAsync.value ?? const <Poll>[];
    if (polls.isEmpty && !canCreate) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, size: 16, color: Color(0xFFB05ECC)),
              const SizedBox(width: 6),
              const Text('Polls',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (canCreate)
                TextButton.icon(
                  onPressed: () => showCreatePollSheet(
                    context,
                    parentPath: parentPath,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          for (final p in polls) PollTile(parentPath: parentPath, poll: p),
        ],
      ),
    );
  }
}

class PollTile extends ConsumerWidget {
  final String parentPath;
  final Poll poll;

  const PollTile({super.key, required this.parentPath, required this.poll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(authStateProvider).value?.uid;
    final key = '$parentPath::${poll.id}';
    final votes = ref.watch(pollVotesProvider(key)).value ?? const [];
    final myVote = ref.watch(myVoteProvider(key)).value;
    final isCreator = myUid != null && myUid == poll.createdByUid;

    final counts = <int, int>{};
    for (final v in votes) {
      counts[v.optionIndex] = (counts[v.optionIndex] ?? 0) + 1;
    }
    final total = votes.length;
    final isSecret = poll.visibility == PollVisibility.secret;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  poll.question,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSecret
                      ? Colors.grey.shade200
                      : context.purpleSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isSecret ? 'SECRET' : 'PUBLIC',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: isSecret
                        ? Colors.grey.shade700
                        : const Color(0xFFB05ECC),
                  ),
                ),
              ),
              if (isCreator && !poll.closed)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => ref
                      .read(pollServiceProvider)
                      .closePoll(parentPath, poll.id),
                  tooltip: 'Close poll',
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < poll.options.length; i++)
            _PollOptionRow(
              label: poll.options[i],
              count: counts[i] ?? 0,
              total: total,
              isMine: myVote?.optionIndex == i,
              disabled: poll.closed,
              onTap: poll.closed
                  ? null
                  : () => ref.read(pollServiceProvider).castVote(
                        parentPath: parentPath,
                        pollId: poll.id,
                        optionIndex: i,
                      ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$total ${total == 1 ? "vote" : "votes"}'
                '${poll.closed ? " · closed" : ""}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final bool isMine;
  final bool disabled;
  final VoidCallback? onTap;

  const _PollOptionRow({
    required this.label,
    required this.count,
    required this.total,
    required this.isMine,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Progress fill
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct.clamp(0, 1),
                  child: Container(
                    color: isMine
                        ? const Color(0xFFE5C4F2)
                        : const Color(0xFFE8EAF0),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isMine
                        ? const Color(0xFFB05ECC)
                        : context.borderColor,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    if (isMine)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.check_circle,
                            size: 14, color: Color(0xFFB05ECC)),
                      ),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isMine
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      total == 0
                          ? '0%'
                          : '${(pct * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
