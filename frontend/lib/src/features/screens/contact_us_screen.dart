import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/contact_request_providers.dart';
import '../../services/contact_request_service.dart';
import '../../theme/app_theme.dart';

/// User-facing "Contact us" entry. Opened from Settings. Lets the
/// signed-in user file a new support thread (general message or
/// organization request) and review any past threads with the admin
/// team's replies inline.
class ContactUsScreen extends ConsumerWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myThreads = ref.watch(myContactRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New request'),
        onPressed: () => _openComposer(context),
      ),
      body: SafeArea(
        child: myThreads.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text('Could not load your requests: $e')),
          data: (threads) {
            if (threads.isEmpty) {
              return _EmptyHint(onTap: () => _openComposer(context));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = threads[i];
                return _ThreadTile(
                  request: t,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContactThreadScreen(request: t),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _openComposer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _NewRequestScreen()),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent_outlined,
                size: 56, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Need help or want to publish events?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to the Iter team. Pick "Organization" if '
              'you want to be approved to post events.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white,
              ),
              onPressed: onTap,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Start a new request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final ContactRequest request;
  final VoidCallback onTap;

  const _ThreadTile({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOrg = request.type == ContactRequestType.organization;
    final unread = request.unreadByUser;
    final status = request.status;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOrg
                          ? AppColors.purple.withValues(alpha: 0.12)
                          : context.surfaceSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOrg ? 'ORGANIZATION' : 'MESSAGE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: isOrg
                            ? AppColors.purple
                            : context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(status: status),
                  const Spacer(),
                  if (unread)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                request.subject.isEmpty ? '(no subject)' : request.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                request.lastMessagePreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(request.lastMessageAt ?? request.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ContactRequestStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContactRequestStatus.open => ('Awaiting reply', Colors.orange),
      ContactRequestStatus.answered => ('Answered', Colors.green),
      ContactRequestStatus.promoted => ('Approved', AppColors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

/// "New request" composer. Picks a type, captures the first message,
/// then files the thread and opens it.
class _NewRequestScreen extends ConsumerStatefulWidget {
  const _NewRequestScreen();

  @override
  ConsumerState<_NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends ConsumerState<_NewRequestScreen> {
  ContactRequestType _type = ContactRequestType.message;
  final _bodyCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Please write a message.');
      return;
    }
    final auth = ref.read(authStateProvider).value;
    final profile = ref.read(currentUserDocProvider).valueOrNull;
    if (auth == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final email = (profile?['email'] as String?) ??
          auth.email ??
          '';
      final name = (profile?['username'] as String?) ??
          (auth.displayName ?? '');
      final id =
          await ref.read(contactRequestServiceProvider).submit(
                userUid: auth.uid,
                userEmail: email,
                userName: name,
                type: _type,
                firstMessage: body,
              );
      if (!mounted) return;
      // Replace the composer with the live thread screen so the user
      // sees their message land and any future admin reply inline.
      final placeholder = ContactRequest(
        id: id,
        userUid: auth.uid,
        userEmail: email,
        userName: name,
        type: _type,
        subject: body.length > 60 ? '${body.substring(0, 59)}…' : body,
        status: ContactRequestStatus.open,
        createdAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessagePreview: body,
        unreadByUser: false,
        unreadByAdmin: true,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ContactThreadScreen(request: placeholder),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).value;
    final profile = ref.watch(currentUserDocProvider).valueOrNull;
    final email = (profile?['email'] as String?) ?? auth?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: context.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  email.isNotEmpty ? email : '(no email on account)',
                  style: TextStyle(
                      color: context.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              Text('Type',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary)),
              const SizedBox(height: 6),
              _TypeChoice(
                value: _type,
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 16),
              Text('Message',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                minLines: 5,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _type == ContactRequestType.organization
                      ? 'Tell us about your organization: what it does, '
                          'why you want to post events, any links.'
                      : 'How can we help?',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChoice extends StatelessWidget {
  final ContactRequestType value;
  final ValueChanged<ContactRequestType> onChanged;
  const _TypeChoice({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tile(ContactRequestType t, String label, String subtitle,
        IconData icon) {
      final selected = value == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.purple.withValues(alpha: 0.10)
                  : context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.purple : context.borderColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 22,
                    color:
                        selected ? AppColors.purple : context.textSecondary),
                const SizedBox(height: 8),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                      height: 1.3,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(ContactRequestType.message, 'Message',
            'Question, feedback, or report a problem.', Icons.chat_outlined),
        const SizedBox(width: 10),
        tile(ContactRequestType.organization, 'Organization',
            'Get approved to post events on Iter.', Icons.apartment_outlined),
      ],
    );
  }
}

/// Chat-style thread view. Both the user-side and the admin-side use
/// this same screen; the reply input adapts to whoever is signed in.
class ContactThreadScreen extends ConsumerStatefulWidget {
  final ContactRequest request;

  const ContactThreadScreen({super.key, required this.request});

  @override
  ConsumerState<ContactThreadScreen> createState() =>
      _ContactThreadScreenState();
}

class _ContactThreadScreenState extends ConsumerState<ContactThreadScreen> {
  final _replyCtrl = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _markedRead = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(bool isAdmin) async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    final senderUid = ref.read(authStateProvider).value?.uid;
    if (senderUid == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(contactRequestServiceProvider).sendMessage(
            requestId: widget.request.id,
            senderUid: senderUid,
            senderIsAdmin: isAdmin,
            body: body,
          );
      _replyCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _promote(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve as organization?'),
        content: Text(
          'This will let ${widget.request.userName.isNotEmpty ? widget.request.userName : widget.request.userEmail} '
          'create events on Iter. They will not gain any other admin '
          'permissions. You can revoke this later by changing their '
          'role back to "user" in the Users panel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    try {
      await ref.read(contactRequestServiceProvider).promoteToOrgAdmin(
            requestId: widget.request.id,
            userUid: widget.request.userUid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization approved.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Promotion failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    // Whichever side opens the thread, flip their unread flag off
    // once per build. Cheap idempotent write.
    if (!_markedRead) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(contactRequestServiceProvider).markRead(
              requestId: widget.request.id,
              readerIsAdmin: isAdmin,
            );
      });
    }
    final msgsAsync =
        ref.watch(contactRequestMessagesProvider(widget.request.id));
    final isOrgRequest =
        widget.request.type == ContactRequestType.organization;
    final canPromote = isAdmin &&
        isOrgRequest &&
        widget.request.status != ContactRequestStatus.promoted;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // User-side always sees "Iter support" — the thread is
              // their conversation WITH support, not with themselves.
              // Admin-side sees the requesting user's identity so they
              // know who they're talking to at a glance.
              isAdmin
                  ? (widget.request.userName.isNotEmpty
                      ? widget.request.userName
                      : widget.request.userEmail.isNotEmpty
                          ? widget.request.userEmail
                          : 'User')
                  : 'Iter support',
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
            if (isAdmin && widget.request.userEmail.isNotEmpty)
              Text(
                widget.request.userEmail,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          if (canPromote)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.purple,
                ),
                onPressed: () => _promote(context),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Approve org'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: msgsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Text('No messages yet.',
                          style:
                              TextStyle(color: context.textSecondary)),
                    );
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollController.hasClients) return;
                    _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent);
                  });
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final fromAdmin = m.senderRole == 'admin';
                      // Visually, the signed-in user's own messages
                      // are on the right. Admins see their replies on
                      // the right; the user sees the same admin reply
                      // on the left.
                      final isMine = fromAdmin == isAdmin;
                      return _Bubble(
                        body: m.body,
                        time: m.createdAt,
                        isMine: isMine,
                        fromAdmin: fromAdmin,
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                border: Border(
                  top: BorderSide(color: context.borderColor),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: isAdmin ? 'Reply to user…' : 'Type a reply…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : () => _send(isAdmin),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String body;
  final DateTime? time;
  final bool isMine;
  final bool fromAdmin;
  const _Bubble({
    required this.body,
    required this.time,
    required this.isMine,
    required this.fromAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = isMine ? AppColors.purple : context.cardBg;
    final textColor = isMine ? Colors.white : context.textPrimary;
    final timeColor =
        isMine ? Colors.white.withValues(alpha: 0.8) : context.textSecondary;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 2),
            bottomRight: Radius.circular(isMine ? 2 : 14),
          ),
          border: isMine
              ? null
              : Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine && fromAdmin) ...[
              Text(
                'Iter support',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 3),
            ],
            Text(
              body,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(time),
                style: TextStyle(fontSize: 10, color: timeColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(time.year, time.month, time.day);
  final daysAgo = today.difference(that).inDays;
  if (daysAgo == 0) return DateFormat.jm().format(time);
  if (daysAgo == 1) return 'Yesterday, ${DateFormat.jm().format(time)}';
  if (daysAgo < 7) {
    return '${DateFormat.E().format(time)}, ${DateFormat.jm().format(time)}';
  }
  return DateFormat.MMMd().add_jm().format(time);
}
