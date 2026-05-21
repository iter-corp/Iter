import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/contact_request_providers.dart';
import '../../services/contact_request_service.dart';
import '../../theme/app_theme.dart';
import 'user_screen.dart';

/// User-facing "Contact us" entry. Opened from Settings. This now
/// routes straight into the user's single ongoing conversation with
/// the Iter team instead of showing a list of separate requests.
class ContactUsScreen extends ConsumerWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).value;
    final profile = ref.watch(currentUserDocProvider).valueOrNull;
    final myThreads = ref.watch(myContactRequestsProvider);
    if (auth == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact us')),
        body: Center(
          child: Text(
            'You need to sign in first.',
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      );
    }
    return myThreads.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Contact us')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Contact us')),
        body: Center(child: Text('Could not open chat: $e')),
      ),
      data: (threads) {
        final active = threads.isNotEmpty
            ? threads.first
            : ContactRequest(
                id: '',
                userUid: auth.uid,
                userEmail: (profile?['email'] as String?) ?? auth.email ?? '',
                userName: (profile?['username'] as String?) ??
                    (auth.displayName ?? ''),
                type: ContactRequestType.message,
                subject: '',
                status: ContactRequestStatus.open,
                createdAt: null,
                lastMessageAt: null,
                lastMessagePreview: '',
                unreadByUser: false,
                unreadByAdmin: false,
              );
        return ContactThreadScreen(request: active);
      },
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
              'Send a message to the Iter team. Pick "Event manager" if '
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOrg
                          ? AppColors.purple.withValues(alpha: 0.12)
                          : context.surfaceSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOrg ? 'EVENT MANAGER' : 'MESSAGE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: isOrg ? AppColors.purple : context.textSecondary,
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
      ContactRequestStatus.revoked => ('Access revoked', Colors.red),
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
      final email = (profile?['email'] as String?) ?? auth.email ?? '';
      final name =
          (profile?['username'] as String?) ?? (auth.displayName ?? '');
      final id = await ref.read(contactRequestServiceProvider).submit(
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
    } on ContactRequestDailyLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: context.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  email.isNotEmpty ? email : '(no email on account)',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
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
                      ? 'Tell us about your event plans, what you manage, '
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
    Widget tile(
        ContactRequestType t, String label, String subtitle, IconData icon) {
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
                    color: selected ? AppColors.purple : context.textSecondary),
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
        tile(
            ContactRequestType.organization,
            'Event manager',
            'Get approved to manage and post events on Iter.',
            Icons.apartment_outlined),
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
  late bool _orgApproved;
  late String _requestId;
  late ContactRequestType _requestType;

  @override
  void initState() {
    super.initState();
    _orgApproved = widget.request.status == ContactRequestStatus.promoted;
    _requestId = widget.request.id;
    _requestType = widget.request.type;
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(bool isAdmin) async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    final auth = ref.read(authStateProvider).value;
    final senderUid = auth?.uid;
    if (senderUid == null) return;
    setState(() => _sending = true);
    try {
      if (!isAdmin && _requestId.isEmpty) {
        final profile = ref.read(currentUserDocProvider).valueOrNull;
        final email = (profile?['email'] as String?) ?? auth?.email ?? '';
        final name =
            (profile?['username'] as String?) ?? (auth?.displayName ?? '');
        final id = await ref.read(contactRequestServiceProvider).submit(
              userUid: senderUid,
              userEmail: email,
              userName: name,
              type: _requestType,
              firstMessage: body,
            );
        if (mounted) {
          setState(() => _requestId = id);
        }
      } else {
        await ref.read(contactRequestServiceProvider).sendMessage(
              requestId: _requestId,
              senderUid: senderUid,
              senderIsAdmin: isAdmin,
              body: body,
            );
      }
      _replyCtrl.clear();
    } on ContactRequestDailyLimitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeType(ContactRequestType type) async {
    if (_requestType == type) return;
    final previousType = _requestType;
    setState(() => _requestType = type);
    if (_requestId.isEmpty) return;
    try {
      await ref.read(contactRequestServiceProvider).setType(
            requestId: _requestId,
            type: type,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestType = previousType);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request type: $e')),
      );
    }
  }

  Future<void> _promote(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve as organization?'),
        content: Text(
          'This will let ${widget.request.userName.isNotEmpty ? widget.request.userName : widget.request.userEmail} '
          'become an event manager on Iter. They will not gain any other '
          'admin permissions. You can revoke this later from this same thread.',
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
      if (mounted) {
        setState(() => _orgApproved = true);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event manager approved.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Promotion failed: $e')),
      );
    }
  }

  Future<void> _revoke(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke organization access?'),
        content: Text(
          'This will remove event manager access for '
          '${widget.request.userName.isNotEmpty ? widget.request.userName : widget.request.userEmail} '
          'and change their role back to user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    try {
      await ref.read(contactRequestServiceProvider).revokeOrgAdmin(
            requestId: widget.request.id,
            userUid: widget.request.userUid,
          );
      if (mounted) {
        setState(() => _orgApproved = false);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event manager access revoked.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Revoke failed: $e')),
      );
    }
  }

  Future<void> _handleAdminUserAction({
    required BuildContext context,
    required String uid,
    required String action,
    required String role,
    required bool suspended,
  }) async {
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
          if (_requestId.isNotEmpty) {
            if (isRevoking) {
              await ref.read(contactRequestServiceProvider).revokeOrgAdmin(
                    requestId: _requestId,
                    userUid: uid,
                  );
              if (mounted) {
                setState(() => _orgApproved = false);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Event manager access revoked.'),
                  ),
                );
              }
            } else {
              await ref.read(contactRequestServiceProvider).promoteToOrgAdmin(
                    requestId: _requestId,
                    userUid: uid,
                  );
              if (mounted) {
                setState(() => _orgApproved = true);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Event manager approved.'),
                  ),
                );
              }
            }
          } else {
            await admin.setRole(uid, isRevoking ? 'user' : 'org_admin');
          }
        }
      } else if (action == 'suspend') {
        await admin.suspendUser(uid, !suspended);
      } else if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete user permanently?'),
            content: const Text(
              'This will delete ALL user data: posts, comments, stories, chats, followers, and notifications. Their email will be blacklisted.\n\nThis cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete everything',
                  style: TextStyle(color: Colors.red),
                ),
              ),
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
    } catch (e, st) {
      print('[admin] action=$action failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    // Whichever side opens the thread, flip their unread flag off
    // once per build. Cheap idempotent write.
    if (_requestId.isNotEmpty && !_markedRead) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(contactRequestServiceProvider).markRead(
              requestId: _requestId,
              readerIsAdmin: isAdmin,
            );
      });
    }
    final msgsAsync = _requestId.isEmpty
        ? const AsyncValue<List<ContactRequestMessage>>.data(
            <ContactRequestMessage>[],
          )
        : ref.watch(contactRequestMessagesProvider(_requestId));
    final isOrgRequest = _requestType == ContactRequestType.organization;
    final canEditType = !isAdmin &&
        !_orgApproved &&
        widget.request.status != ContactRequestStatus.revoked;
    final requesterLive = isAdmin && widget.request.userUid.isNotEmpty
        ? ref.watch(userByUidProvider(widget.request.userUid)).valueOrNull
        : null;
    final requesterName =
        ((requesterLive?['username'] as String?)?.trim().isNotEmpty ?? false)
            ? (requesterLive!['username'] as String).trim()
            : widget.request.userName.isNotEmpty
                ? widget.request.userName
                : widget.request.userEmail.isNotEmpty
                    ? widget.request.userEmail
                    : 'User';
    final requesterEmail =
        ((requesterLive?['email'] as String?)?.trim().isNotEmpty ?? false)
            ? (requesterLive!['email'] as String).trim()
            : widget.request.userEmail;
    final requesterAvatar =
        ((requesterLive?['avatarUrl'] as String?)?.trim().isNotEmpty ?? false)
            ? (requesterLive!['avatarUrl'] as String).trim()
            : '';
    final requesterRole = (requesterLive?['role'] as String?) ?? 'user';
    final requesterSuspended = (requesterLive?['suspended'] as bool?) ?? false;
    final canManageRequester = isAdmin && widget.request.userUid.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: isAdmin
            ? InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: widget.request.userUid.isEmpty
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                UserProfileScreen(uid: widget.request.userUid),
                          ),
                        );
                      },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: context.inputFill,
                      backgroundImage: requesterAvatar.isNotEmpty
                          ? NetworkImage(requesterAvatar)
                          : null,
                      child: requesterAvatar.isEmpty
                          ? const Icon(Icons.person, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requesterName,
                            style: const TextStyle(fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (requesterEmail.isNotEmpty)
                            Text(
                              requesterEmail,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : const Text('Iter Team'),
        actions: [
          if (canManageRequester)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => _handleAdminUserAction(
                context: context,
                uid: widget.request.userUid,
                action: action,
                role: requesterRole,
                suspended: requesterSuspended,
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'role',
                  child: Text(
                    requesterRole == 'admin'
                        ? 'Demote to user'
                        : 'Promote to admin',
                  ),
                ),
                if (requesterRole != 'admin')
                  PopupMenuItem(
                    value: 'orgRole',
                    child: Text(
                      requesterRole == 'org_admin'
                          ? 'Revoke event manager'
                          : 'Grant event manager',
                    ),
                  ),
                PopupMenuItem(
                  value: 'suspend',
                  child: Text(
                    requesterSuspended ? 'Unsuspend' : 'Suspend',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete user',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (canEditType)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _ThreadTypeBar(
                  value: _requestType,
                  onChanged: _changeType,
                ),
              ),
            Expanded(
              child: msgsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          _requestType == ContactRequestType.organization
                              ? 'Tell Iter Team why you should be approved as an event manager and what events you want to post.'
                              : 'Start the conversation with Iter Team. Your replies will stay in this one chat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                    );
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollController.hasClients) return;
                    _scrollController
                        .jumpTo(_scrollController.position.maxScrollExtent);
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
                        hintText: isAdmin
                            ? 'Reply to user…'
                            : _requestType == ContactRequestType.organization
                                ? 'Tell Iter Team about your event plans…'
                                : 'Type a reply…',
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
    final align = isMine
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
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
          border: isMine ? null : Border.all(color: context.borderColor),
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

class _ThreadTypeBar extends StatelessWidget {
  final ContactRequestType value;
  final ValueChanged<ContactRequestType> onChanged;

  const _ThreadTypeBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(ContactRequestType type, String label, IconData icon) {
      final selected = value == type;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.purple : context.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.purple : context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(ContactRequestType.message, 'Message', Icons.chat_outlined),
        const SizedBox(width: 10),
        chip(
          ContactRequestType.organization,
          'Event manager',
          Icons.apartment_outlined,
        ),
      ],
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
