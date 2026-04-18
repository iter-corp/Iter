import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../theme/app_theme.dart';
import '../../providers/event_chat_providers.dart';
import '../../services/chat_service.dart';
import '../../services/event_chat_service.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/message_widget.dart';
import 'chat_screen.dart';
import 'event_chat_screen.dart';
import 'request_screen.dart';

/// Unified row in the chat list — either a 1:1 chat or an event group chat.
sealed class InboxRow {
  DateTime? get sortTime;
}

class OneToOneRow extends InboxRow {
  final ChatConversation conv;
  OneToOneRow(this.conv);
  @override
  DateTime? get sortTime => conv.lastTime;
}

class EventRow extends InboxRow {
  final EventChatSummary chat;
  EventRow(this.chat);
  @override
  DateTime? get sortTime => chat.lastTime;
}

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const MessageBody(),
    );
  }
}

class MessageBody extends ConsumerStatefulWidget {
  const MessageBody({super.key});

  @override
  ConsumerState<MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends ConsumerState<MessageBody> {
  int selectedTab = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(ChatConversation c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.otherUsername.toLowerCase().contains(q) ||
        c.lastMessage.toLowerCase().contains(q);
  }

  void _openChat(ChatConversation conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: conv.chatId,
          otherUid: conv.otherUid,
          otherName: conv.isGroup ? conv.groupName : conv.otherUsername,
          otherAvatar:
              conv.isGroup ? conv.groupAvatarUrl : conv.otherAvatarUrl,
        ),
      ),
    );
  }

  void _openEventChat(EventChatSummary chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventChatScreen(
          eventId: chat.eventId,
          eventTitle: chat.eventTitle,
          adminUid: chat.adminUid,
        ),
      ),
    );
  }

  bool _matchesEvent(EventChatSummary c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.eventTitle.toLowerCase().contains(q) ||
        c.lastMessage.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final acceptedInboxAsync = ref.watch(acceptedInboxProvider);
    final requestsAsync = ref.watch(requestsProvider);
    final eventChatsAsync = ref.watch(myEventChatsProvider);

    final oneToOne = (acceptedInboxAsync.value ?? []).where(_matches).toList();
    final eventRows =
        (eventChatsAsync.value ?? []).where(_matchesEvent).toList();
    final requestConvs = (requestsAsync.value ?? []).where(_matches).toList();

    // Merge + sort by lastTime (newest first).
    final merged = <InboxRow>[
      ...oneToOne.map((c) => OneToOneRow(c)),
      ...eventRows.map((c) => EventRow(c)),
    ];
    merged.sort((a, b) {
      if (a.sortTime == null) return 1;
      if (b.sortTime == null) return -1;
      return b.sortTime!.compareTo(a.sortTime!);
    });

    return SafeArea(
      child: Column(
        children: [
          // ── Search bar + New group ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: context.inputFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle:
                            TextStyle(color: context.textMuted, fontSize: 14),
                        border: InputBorder.none,
                        icon: Icon(Icons.search, color: context.textSecondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFFB05ECC),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => showCreateGroupSheet(context),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      child: Icon(
                        Icons.group_add_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Tab bar ─────────────────────────────────────────────────
          MessageTabBar(
            selectedTab: selectedTab,
            allCount: merged.length,
            requestCount: requestConvs.length,
            onTap: (i) => setState(() => selectedTab = i),
          ),
          const SizedBox(height: 8),

          // ── Conversation list ────────────────────────────────────────
          Expanded(
            child: selectedTab == 0
                ? acceptedInboxAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (_) {
                      if (merged.isEmpty) {
                        return Center(
                          child: Text(
                            'No messages yet',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: merged.length,
                        itemBuilder: (_, i) {
                          final row = merged[i];
                          if (row is OneToOneRow) {
                            return _ConvTile(
                              conv: row.conv,
                              onTap: () => _openChat(row.conv),
                            );
                          }
                          if (row is EventRow) {
                            return _EventConvTile(
                              chat: row.chat,
                              onTap: () => _openEventChat(row.chat),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  )
                : requestsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (_) {
                      return RequestsTab(
                        requests: requestConvs,
                        onTap: _openChat,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Private conversation tile
// ─────────────────────────────────────────────

class _ConvTile extends StatelessWidget {
  final ChatConversation conv;
  final VoidCallback onTap;

  const _ConvTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = conv.isGroup ? conv.groupName : conv.otherUsername;
    final displayAvatar =
        conv.isGroup ? conv.groupAvatarUrl : conv.otherAvatarUrl;
    return ListTile(
      onTap: onTap,
      leading: conv.isGroup
          ? CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF7E3BE8),
              backgroundImage: displayAvatar.isNotEmpty
                  ? NetworkImage(displayAvatar)
                  : null,
              child: displayAvatar.isEmpty
                  ? const Icon(Icons.groups, color: Colors.white)
                  : null,
            )
          : CircleAvatar(
              radius: 26,
              backgroundColor: context.inputFill,
              backgroundImage: displayAvatar.isNotEmpty
                  ? NetworkImage(displayAvatar)
                  : null,
              child: displayAvatar.isEmpty
                  ? Icon(Icons.person, color: context.textSecondary)
                  : null,
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.isGroup) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEADDF7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'GROUP',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFF7E3BE8),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        conv.lastMessage,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conv.unreadCount > 0)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFB05ECC),
                shape: BoxShape.circle,
              ),
            ),
          Icon(Icons.camera_alt_outlined, size: 20, color: context.textSecondary),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Event group chat tile
// ─────────────────────────────────────────────

class _EventConvTile extends StatelessWidget {
  final EventChatSummary chat;
  final VoidCallback onTap;

  const _EventConvTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = chat.lastMessage.isEmpty ? 'Event group' : chat.lastMessage;
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(
        radius: 26,
        backgroundColor: Color(0xFFB05ECC),
        child: Icon(Icons.groups, color: Colors.white),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              chat.eventTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.purpleSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'EVENT',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFFB05ECC),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        preview,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: chat.unreadCount > 0
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFB05ECC),
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
