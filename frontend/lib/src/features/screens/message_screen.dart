import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/follow_providers.dart';
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
          otherAvatar: conv.isGroup ? conv.groupAvatarUrl : conv.otherAvatarUrl,
        ),
      ),
    );
  }

  /// Open (or create) a 1:1 chat with [otherUid]. Used when the search
  /// matches a followed user the current user hasn't messaged yet — we
  /// build the chat doc on the fly so they can start typing immediately.
  Future<void> _openChatWithUser({
    required String otherUid,
    required String otherName,
    required String otherAvatar,
  }) async {
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;
    final chatService = ref.read(chatServiceProvider);
    final chatId = await chatService.openChat(
      currentUid: currentUid,
      otherUid: otherUid,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          otherUid: otherUid,
          otherName: otherName,
          otherAvatar: otherAvatar,
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
    final inboxAsync = ref.watch(inboxProvider);
    final requestsAsync = ref.watch(requestsProvider);
    final eventChatsAsync = ref.watch(myEventChatsProvider);

    final oneToOne = (inboxAsync.valueOrNull ?? []).where(_matches).toList();
    final eventRows =
        (eventChatsAsync.valueOrNull ?? []).where(_matchesEvent).toList();
    final requestConvs =
        (requestsAsync.valueOrNull ?? []).where(_matches).toList();

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
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                ? inboxAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (_) {
                      // When the search box has a query, also surface
                      // followed users the user hasn't messaged yet so
                      // they can start a new chat directly from results.
                      final query = _query.trim();
                      final hasQuery = query.isNotEmpty;
                      final existingUids = {
                        for (final r in merged)
                          if (r is OneToOneRow) r.conv.otherUid,
                      };
                      return _SearchableConvList(
                        merged: merged,
                        query: query,
                        hasQuery: hasQuery,
                        existingUids: existingUids,
                        onOpenConv: _openChat,
                        onOpenEvent: _openEventChat,
                        onStartChat: _openChatWithUser,
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
// Searchable conversation list
// ─────────────────────────────────────────────

/// Renders the inbox plus, when a search query is active, a "People you
/// follow" section with followed users the current user hasn't messaged
/// yet. Tapping such a user opens (or creates) a new chat with them.
class _SearchableConvList extends ConsumerWidget {
  final List<InboxRow> merged;
  final String query;
  final bool hasQuery;
  final Set<String> existingUids;
  final void Function(ChatConversation) onOpenConv;
  final void Function(EventChatSummary) onOpenEvent;
  final Future<void> Function({
    required String otherUid,
    required String otherName,
    required String otherAvatar,
  }) onStartChat;

  const _SearchableConvList({
    required this.merged,
    required this.query,
    required this.hasQuery,
    required this.existingUids,
    required this.onOpenConv,
    required this.onOpenEvent,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final followingAsync = currentUid == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(followingProvider(currentUid));
    final followingUids = followingAsync.valueOrNull ?? const <String>[];

    final showFollowed = hasQuery && currentUid != null;
    final candidateFollowedUids = showFollowed
        ? followingUids.where((uid) => !existingUids.contains(uid)).toList()
        : const <String>[];

    if (merged.isEmpty && !showFollowed) {
      return Center(
        child: Text(
          'No messages yet',
          style: TextStyle(color: context.textSecondary),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: merged.length,
          itemBuilder: (_, i) {
            final row = merged[i];
            if (row is OneToOneRow) {
              return _ConvTile(
                conv: row.conv,
                onTap: () => onOpenConv(row.conv),
              );
            }
            if (row is EventRow) {
              return _EventConvTile(
                chat: row.chat,
                onTap: () => onOpenEvent(row.chat),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        if (showFollowed)
          SliverToBoxAdapter(
            child: _FollowedPeopleSection(
              followedUids: candidateFollowedUids,
              query: query,
              hasExistingChats: merged.isNotEmpty,
              onStartChat: onStartChat,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

/// Section header + tappable rows for followed users matching [query]
/// that the current user has no chat with yet. Each row resolves the
/// user's live profile via [userByUidProvider] so we always show the
/// freshest username/avatar.
class _FollowedPeopleSection extends ConsumerWidget {
  final List<String> followedUids;
  final String query;
  final bool hasExistingChats;
  final Future<void> Function({
    required String otherUid,
    required String otherName,
    required String otherAvatar,
  }) onStartChat;

  const _FollowedPeopleSection({
    required this.followedUids,
    required this.query,
    required this.hasExistingChats,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (followedUids.isEmpty) {
      if (hasExistingChats) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Text(
            'No matches',
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasExistingChats) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            'People you follow',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        for (final uid in followedUids)
          _FollowedUserTile(
            uid: uid,
            query: query,
            onTap: ({required name, required avatar}) => onStartChat(
              otherUid: uid,
              otherName: name,
              otherAvatar: avatar,
            ),
          ),
      ],
    );
  }
}

class _FollowedUserTile extends ConsumerWidget {
  final String uid;
  final String query;
  final void Function({required String name, required String avatar}) onTap;

  const _FollowedUserTile({
    required this.uid,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByUidProvider(uid));
    final data = userAsync.value;
    if (data == null) {
      // Don't render a hollow row while the user doc resolves.
      return const SizedBox.shrink();
    }
    final username = (data['username'] as String?) ?? '';
    final fullName = (data['fullName'] as String?) ?? '';
    final avatar = (data['avatarUrl'] as String?) ?? '';
    final q = query.toLowerCase();
    if (q.isNotEmpty &&
        !username.toLowerCase().contains(q) &&
        !fullName.toLowerCase().contains(q)) {
      return const SizedBox.shrink();
    }
    return ListTile(
      onTap: () => onTap(
        name: username.isNotEmpty
            ? username
            : (fullName.isNotEmpty ? fullName : 'User'),
        avatar: avatar,
      ),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: context.inputFill,
        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
        child: avatar.isEmpty
            ? Icon(Icons.person, color: context.textSecondary)
            : null,
      ),
      title: Text(
        username.isNotEmpty ? username : 'User',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.textPrimary,
        ),
      ),
      subtitle: Text(
        fullName.isNotEmpty ? fullName : 'Tap to start a chat',
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: Icon(Icons.chat_bubble_outline,
          size: 18, color: context.textSecondary),
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
              backgroundImage:
                  displayAvatar.isNotEmpty ? NetworkImage(displayAvatar) : null,
              child: displayAvatar.isEmpty
                  ? const Icon(Icons.groups, color: Colors.white)
                  : null,
            )
          : CircleAvatar(
              radius: 26,
              backgroundColor: context.inputFill,
              backgroundImage:
                  displayAvatar.isNotEmpty ? NetworkImage(displayAvatar) : null,
              child: displayAvatar.isEmpty
                  ? Icon(Icons.person, color: context.textSecondary)
                  : null,
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: context.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.isGroup) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.purpleSoft,
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
        conv.unreadCount > 0
            ? '${conv.unreadCount} new ${conv.unreadCount == 1 ? 'message' : 'messages'}'
            : conv.lastMessage,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: conv.unreadCount > 0
          ? _UnreadCountBadge(count: conv.unreadCount)
          : null,
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
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: context.textPrimary,
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
        chat.unreadCount > 0
            ? '${chat.unreadCount} new ${chat.unreadCount == 1 ? 'message' : 'messages'}'
            : preview,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: chat.unreadCount > 0
          ? _UnreadCountBadge(count: chat.unreadCount)
          : null,
    );
  }
}

class _UnreadCountBadge extends StatelessWidget {
  final int count;

  const _UnreadCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const BoxDecoration(
        color: Color(0xFFB05ECC),
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      constraints: const BoxConstraints(minWidth: 20),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
