import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/contact_request_providers.dart';
import '../../services/contact_request_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
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
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.t.contactUs),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        ),
        body: AppPageBackground(
          child: Center(
            child: Text(
              context.t.contactNeedSignIn,
              style: TextStyle(color: context.textSecondary),
            ),
          ),
        ),
      );
    }
    return myThreads.when(
      loading: () => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.t.contactUs),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        ),
        body: const AppPageBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.t.contactUs),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        ),
        body: AppPageBackground(
          child: Center(child: Text('${context.t.contactCouldNotOpen}: $e')),
        ),
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
      setState(() => _error = context.t.contactPleaseWriteMessage);
      return;
    }
    final auth = ref.read(authStateProvider).value;
    final profile = ref.read(currentUserDocProvider).valueOrNull;
    if (auth == null) {
      setState(() => _error = context.t.contactNotSignedIn);
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
        _error = context.t.contactCouldNotSubmit(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).value;
    final profile = ref.watch(currentUserDocProvider).valueOrNull;
    final email = (profile?['email'] as String?) ?? auth?.email ?? '';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.contactNewRequest),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: SafeArea(
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t.contactFromLabel,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary)),
              const SizedBox(height: 6),
              AppGlassCard(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text(
                  email.isNotEmpty ? email : context.t.contactNoEmail,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.t.contactTypeLabel,
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
              Text(context.t.contactMessageLabel,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary)),
              const SizedBox(height: 6),
              AppGlassCard(
                radius: 16,
                padding: EdgeInsets.zero,
                child: TextField(
                  controller: _bodyCtrl,
                  minLines: 5,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _type == ContactRequestType.organization
                        ? context.t.contactOrgHint
                        : context.t.contactHowCanWeHelp,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
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
                      : Text(context.t.contactSendRequest),
                ),
              ),
            ],
          ),
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
          child: AppGlassCard(
            radius: 14,
            emphasize: selected,
            surfaceAlpha: context.isDark ? 0.42 : 0.36,
            borderAlpha: selected ? 0.65 : (context.isDark ? 0.14 : 0.50),
            padding: const EdgeInsets.all(12),
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
        tile(ContactRequestType.message, context.t.contactTypeMessage,
            context.t.contactTypeMessageDesc, Icons.chat_outlined),
        const SizedBox(width: 10),
        tile(
            ContactRequestType.organization,
            context.t.contactTypeOrg,
            context.t.contactTypeOrgDesc,
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
        SnackBar(content: Text(context.t.contactFailedSend(e))),
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
        SnackBar(content: Text(context.t.contactCouldNotUpdateType(e))),
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
                ? context.t.contactRevokeOrgTitle
                : context.t.contactGrantOrgTitle),
            content: Text(isRevoking
                ? context.t.contactRevokeOrgBody
                : context.t.contactGrantOrgBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isRevoking
                    ? context.t.contactRevoke
                    : context.t.contactGrant),
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
                  SnackBar(
                    content: Text(context.t.contactOrgRevoked),
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
                  SnackBar(
                    content: Text(context.t.contactOrgApproved),
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
            title: Text(context.t.contactDeleteUserTitle),
            content: Text(context.t.contactDeleteUserBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  context.t.contactDeleteEverything,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
        if (ok == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.contactDeletingAll)),
            );
          }
          await admin.deleteUser(uid);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.contactUserDeleted)),
            );
          }
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.contactGenericFailed(e))));
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
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
            : Text(context.t.contactIterTeam),
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
                        ? context.t.contactDemoteToUser
                        : context.t.contactPromoteToAdmin,
                  ),
                ),
                if (requesterRole != 'admin')
                  PopupMenuItem(
                    value: 'orgRole',
                    child: Text(
                      requesterRole == 'org_admin'
                          ? context.t.contactRevokeEventManager
                          : context.t.contactGrantEventManager,
                    ),
                  ),
                PopupMenuItem(
                  value: 'suspend',
                  child: Text(
                    requesterSuspended
                        ? context.t.contactUnsuspend
                        : context.t.contactSuspend,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    context.t.contactDeleteUser,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: AppPageBackground(
        child: SafeArea(
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
                error: (e, _) =>
                    Center(child: Text(context.t.contactErrorPrefix(e))),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          _requestType == ContactRequestType.organization
                              ? context.t.contactEmptyOrgMessage
                              : context.t.contactEmptyMessage,
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
            AppGlassCard(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              radius: 24,
              surfaceAlpha: context.isDark ? 0.46 : 0.38,
              borderAlpha: context.isDark ? 0.14 : 0.50,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                            ? context.t.contactReplyToUser
                            : _requestType == ContactRequestType.organization
                                ? context.t.contactReplyOrgHint
                                : context.t.contactReplyTypeReply,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
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
                context.t.contactIterSupport,
                style: const TextStyle(
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
                _formatTime(context, time),
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
          child: AppGlassCard(
            radius: 14,
            emphasize: selected,
            surfaceAlpha: context.isDark ? 0.42 : 0.36,
            borderAlpha: selected ? 0.65 : (context.isDark ? 0.14 : 0.50),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        chip(ContactRequestType.message, context.t.contactTypeMessage,
            Icons.chat_outlined),
        const SizedBox(width: 10),
        chip(
          ContactRequestType.organization,
          context.t.contactTypeOrg,
          Icons.apartment_outlined,
        ),
      ],
    );
  }
}

String _formatTime(BuildContext context, DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(time.year, time.month, time.day);
  final daysAgo = today.difference(that).inDays;
  if (daysAgo == 0) return DateFormat.jm().format(time);
  if (daysAgo == 1) {
    return '${context.t.contactYesterday}, ${DateFormat.jm().format(time)}';
  }
  if (daysAgo < 7) {
    return '${DateFormat.E().format(time)}, ${DateFormat.jm().format(time)}';
  }
  return DateFormat.MMMd().add_jm().format(time);
}
