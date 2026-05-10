import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../navigation/user_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../services/event_chat_service.dart';
import '../widgets/message_reactions_bar.dart';
import '../widgets/poll_widgets.dart';
import 'event_group_settings_screen.dart';

class EventChatScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final String adminUid;

  const EventChatScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.adminUid,
  });

  @override
  ConsumerState<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends ConsumerState<EventChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? get _currentUid => ref.read(authStateProvider).value?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(eventChatServiceProvider).markSeen(widget.eventId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(eventChatServiceProvider).sendMessage(
          eventId: widget.eventId,
          text: text,
        );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _openAdminProfile() {
    openUserProfile(context, uid: widget.adminUid);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventGroupSettingsScreen(
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
          adminUid: widget.adminUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _currentUid;
    final isAdmin = currentUid != null && currentUid == widget.adminUid;
    final msgsAsync = ref.watch(eventChatMessagesProvider(widget.eventId));
    final adminLive = ref.watch(userByUidProvider(widget.adminUid)).valueOrNull;
    final adminAvatar = (adminLive?['avatarUrl'] as String?) ?? '';
    final adminName = (adminLive?['username'] as String?) ?? 'Admin';

    ref.listen(eventChatMessagesProvider(widget.eventId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  GestureDetector(
                    onTap: _openSettings,
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFB05ECC),
                      child: Icon(Icons.groups, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openSettings,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.eventTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          GestureDetector(
                            onTap: _openAdminProfile,
                            child: Row(
                              children: [
                                if (adminAvatar.isNotEmpty)
                                  CircleAvatar(
                                    radius: 7,
                                    backgroundImage:
                                        CachedNetworkImageProvider(adminAvatar),
                                  ),
                                if (adminAvatar.isNotEmpty)
                                  const SizedBox(width: 4),
                                Text(
                                  'Admin: $adminName',
                                  style: const TextStyle(
                                    color: Color(0xFFB05ECC),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.more_vert, size: 22),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // MESSAGES
            Expanded(
              child: msgsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (msgs) {
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet.',
                        style: TextStyle(color: context.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final msg = msgs[i];
                      return _EventMessageBubble(
                        eventId: widget.eventId,
                        msg: msg,
                        isMe: msg.senderUid == currentUid,
                        isFromAdmin: msg.senderUid == widget.adminUid,
                      );
                    },
                  );
                },
              ),
            ),

            PollsSection(
              parentPath: 'eventChats/${widget.eventId}',
              canCreate: isAdmin,
            ),

            // INPUT / read-only notice
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: context.inputFill,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Broadcast a message...',
                            hintStyle:
                                TextStyle(color: context.textMuted, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send, color: Color(0xFFB05ECC)),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: context.purpleSoft,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: Color(0xFF8A3FB8)),
                    SizedBox(width: 6),
                    Text(
                      'Only the admin can send messages. You can react.',
                      style: TextStyle(
                        color: Color(0xFF8A3FB8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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

class _EventMessageBubble extends ConsumerWidget {
  final String eventId;
  final EventChatMessage msg;
  final bool isMe;
  final bool isFromAdmin;

  const _EventMessageBubble({
    required this.eventId,
    required this.msg,
    required this.isMe,
    required this.isFromAdmin,
  });

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderLive = ref.watch(userByUidProvider(msg.senderUid)).valueOrNull;
    final senderName =
        (senderLive?['username'] as String?) ?? (isFromAdmin ? 'Admin' : 'User');
    final senderAvatar = (senderLive?['avatarUrl'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => openUserProfile(context, uid: msg.senderUid),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: senderAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(senderAvatar)
                    : null,
                child: senderAvatar.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 4),
                    child: Text(
                      isFromAdmin ? '$senderName · admin' : senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isFromAdmin
                            ? const Color(0xFFB05ECC)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: () => showReactionsSheet(
                    context,
                    ref: ref,
                    parentPath: 'eventChats/$eventId/messages',
                    messageId: msg.id,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFFB05ECC)
                            : context.inputFill,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                      ),
                      child: (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: msg.imageUrl!,
                                    width: 240,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (msg.text.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    msg.text,
                                    style: TextStyle(
                                      color:
                                          isMe ? Colors.white : context.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              msg.text,
                              style: TextStyle(
                                color: isMe ? Colors.white : context.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ),
                MessageReactionsRow(
                  parentPath: 'eventChats/$eventId/messages',
                  messageId: msg.id,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmt(msg.createdAt),
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
