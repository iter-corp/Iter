import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
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
      backgroundColor: Colors.transparent,
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

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: context.isDark
              ? const [Color(0xFF101017), Color(0xFF171726), Color(0xFF11111A)]
              : const [Color(0xFFF8F5FF), Color(0xFFEFF6FF), Color(0xFFFDF7F2)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -30,
            child: _AmbientOrb(
              size: 220,
              color: const Color(0xFF6FA8FF)
                  .withValues(alpha: context.isDark ? 0.12 : 0.18),
            ),
          ),
          Positioned(
            top: 140,
            left: -50,
            child: _AmbientOrb(
              size: 180,
              color: const Color(0xFFC08BFF)
                  .withValues(alpha: context.isDark ? 0.10 : 0.16),
            ),
          ),
          Positioned(
            bottom: -70,
            right: 30,
            child: _AmbientOrb(
              size: 200,
              color: const Color(0xFF6EE7B7)
                  .withValues(alpha: context.isDark ? 0.08 : 0.14),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Search bar + New group ──────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              hintText: context.t.searchWithDots,
                              hintStyle: TextStyle(
                                  color: context.textMuted, fontSize: 14),
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              icon: Icon(Icons.search,
                                  color: context.textSecondary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => showCreateGroupSheet(context),
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.purple,
                                  AppColors.purpleVivid,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.purple
                                      .withValues(alpha: 0.32),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
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
                          error: (e, _) => Center(
                              child: Text(context.t.errorWithMessage(e))),
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
                          error: (e, _) => Center(
                              child: Text(context.t.errorWithMessage(e))),
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
          context.t.noMessages,
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
            context.t.noMatches,
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
            context.t.peopleYouFollow,
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
    final data = userAsync.valueOrNull;
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
            : (fullName.isNotEmpty ? fullName : context.t.user),
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
        username.isNotEmpty ? username : context.t.user,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.textPrimary,
        ),
      ),
      subtitle: Text(
        fullName.isNotEmpty ? fullName : context.t.tapToStartChat,
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

class _ConvTile extends ConsumerWidget {
  final ChatConversation conv;
  final VoidCallback onTap;

  const _ConvTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final isMuted = currentUid != null && conv.isMutedBy(currentUid);

    // For 1:1 chats, watch the peer's live user doc so the avatar +
    // username reflect their CURRENT profile rather than the snapshot
    // taken when the chat was first created. The denormalized
    // userData on the chat doc is kept as a fallback for the first
    // frame (and offline).
    final peerLive = (!conv.isGroup && conv.otherUid.isNotEmpty)
        ? ref.watch(userByUidProvider(conv.otherUid)).valueOrNull
        : null;
    final displayName = conv.isGroup
        ? conv.groupName
        : ((peerLive?['username'] as String?)?.trim().isNotEmpty == true
            ? peerLive!['username'] as String
            : conv.otherUsername);
    final displayAvatar = conv.isGroup
        ? conv.groupAvatarUrl
        : ((peerLive?['avatarUrl'] as String?)?.trim().isNotEmpty == true
            ? peerLive!['avatarUrl'] as String
            : conv.otherAvatarUrl);

    // Presence + typing — only for 1:1 (group chats don't have a
    // single "other party").
    final isOneToOne = !conv.isGroup && conv.otherUid.isNotEmpty;
    final presenceAsync = isOneToOne
        ? ref.watch(presenceWatchProvider(conv.otherUid))
        : null;
    final isOnline =
        presenceAsync?.whenOrNull(data: (p) => p.online) ?? false;
    final typingAsync = (isOneToOne && currentUid != null)
        ? ref.watch(
            typingWatchProvider('${conv.chatId}|${conv.otherUid}'))
        : null;
    final isTyping = typingAsync?.whenOrNull(data: (t) => t) ?? false;

    final hasUnread = conv.unreadCount > 0;
    final timeLabel = _formatInboxTime(conv.lastTime);

    return _GlassChatCard(
      emphasize: hasUnread,
      child: ListTile(
        onTap: onTap,
        onLongPress: currentUid == null
            ? null
            : () => _showChatActions(
                  context: context,
                  ref: ref,
                  conv: conv,
                  currentUid: currentUid,
                  isMuted: isMuted,
                ),
        contentPadding: context.isDark
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Stack(
          children: [
            conv.isGroup
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
            // Green dot indicating the peer is online. Same look as the
            // chat-screen header so the inbox stays visually consistent.
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                style: TextStyle(
                    // Slightly heavier weight when unread so the eye is
                    // drawn down the list to the rows that need
                    // attention, the same trick iOS Messages uses.
                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 15,
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
                child: Text(
                  context.t.groupUppercase,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF7E3BE8),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            if (isMuted) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.notifications_off_outlined,
                size: 14,
                color: context.textSecondary,
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            isTyping ? context.t.typing : conv.lastMessage,
            style: TextStyle(
              color: isTyping
                  ? const Color(0xFFB05ECC)
                  : (hasUnread ? context.textPrimary : context.textSecondary),
              fontSize: 13,
              fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (timeLabel.isNotEmpty)
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      hasUnread ? FontWeight.w600 : FontWeight.w500,
                  color: hasUnread
                      ? const Color(0xFFB05ECC)
                      : context.textSecondary,
                ),
              ),
            if (hasUnread) ...[
              const SizedBox(height: 6),
              _UnreadCountBadge(count: conv.unreadCount),
            ],
          ],
        ),
      ),
    );
  }
}

/// Formats a chat's last-message timestamp for the inbox tile.
///   * Today  → "2:14 PM"
///   * Yesterday → "Yest"
///   * This week → weekday short name ("Mon")
///   * Older → "Nov 12"
String _formatInboxTime(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(time.year, time.month, time.day);
  final daysAgo = today.difference(that).inDays;
  if (daysAgo == 0) return DateFormat.jm().format(time);
  if (daysAgo == 1) return 'Yest';
  if (daysAgo < 7) return DateFormat.E().format(time);
  return DateFormat.MMMd().format(time);
}

// ─────────────────────────────────────────────
// Long-press action sheets
// ─────────────────────────────────────────────

Future<void> _showChatActions({
  required BuildContext context,
  required WidgetRef ref,
  required ChatConversation conv,
  required String currentUid,
  required bool isMuted,
}) async {
  final svc = ref.read(chatServiceProvider);
  final displayName = conv.isGroup ? conv.groupName : conv.otherUsername;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Icon(
                isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: context.textPrimary,
              ),
              title: Text(
                isMuted
                    ? context.t.unmuteNotifications
                    : context.t.muteNotifications,
                style: TextStyle(color: context.textPrimary),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await svc.setMuted(
                    chatId: conv.chatId,
                    uid: currentUid,
                    muted: !isMuted,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMuted
                            ? context.t.notificationsUnmuted
                            : context.t.notificationsMuted,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t.failedWithError(e))),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                context.t.deleteChat,
                style: const TextStyle(color: Colors.red),
              ),
              subtitle: Text(
                conv.isGroup
                    ? context.t.removesGroupAllMessages
                    : context.t.removesConversationBoth,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final confirmed = await _confirmDestructive(
                  context: context,
                  title: context.t.deleteThisChatQuestion,
                  body: conv.isGroup
                      ? context.t.deleteChatGroupBody(displayName)
                      : context.t.deleteChatOneToOneBody(displayName),
                );
                if (confirmed != true) return;
                try {
                  if (conv.isGroup) {
                    await svc.deleteGroup(conv.chatId);
                  } else {
                    await svc.deleteChat(conv.chatId);
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t.chatDeleted)),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t.failedToDelete(e))),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _showEventChatActions({
  required BuildContext context,
  required WidgetRef ref,
  required EventChatSummary chat,
  required String currentUid,
  required bool isMuted,
}) async {
  final svc = ref.read(eventChatServiceProvider);
  final isAdmin = chat.adminUid == currentUid;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  chat.eventTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Icon(
                isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: context.textPrimary,
              ),
              title: Text(
                isMuted
                    ? context.t.unmuteNotifications
                    : context.t.muteNotifications,
                style: TextStyle(color: context.textPrimary),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await svc.setMuted(
                    eventId: chat.eventId,
                    uid: currentUid,
                    muted: !isMuted,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMuted
                            ? context.t.notificationsUnmuted
                            : context.t.notificationsMuted,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t.failedWithError(e))),
                  );
                }
              },
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  context.t.deleteGroup,
                  style: const TextStyle(color: Colors.red),
                ),
                subtitle: Text(
                  context.t.removesGroupAndMessages,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirmed = await _confirmDestructive(
                    context: context,
                    title: context.t.deleteEventGroupQuestion,
                    body:
                        context.t.deleteEventGroupBody(chat.eventTitle),
                  );
                  if (confirmed != true) return;
                  try {
                    await svc.deleteEventGroup(chat.eventId);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t.groupDeleted)),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t.failedToDelete(e))),
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<bool?> _confirmDestructive({
  required BuildContext context,
  required String title,
  required String body,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(context.t.delete),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// Event group chat tile
// ─────────────────────────────────────────────

class _EventConvTile extends ConsumerWidget {
  final EventChatSummary chat;
  final VoidCallback onTap;

  const _EventConvTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider).value?.uid;
    final preview =
        chat.lastMessage.isEmpty ? context.t.eventGroup : chat.lastMessage;
    final isMuted = currentUid != null && chat.isMutedBy(currentUid);
    return _GlassChatCard(
      emphasize: chat.unreadCount > 0,
      child: ListTile(
        onTap: onTap,
        onLongPress: currentUid == null
            ? null
            : () => _showEventChatActions(
                  context: context,
                  ref: ref,
                  chat: chat,
                  currentUid: currentUid,
                  isMuted: isMuted,
                ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
              child: Text(
                context.t.eventUppercase,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFFB05ECC),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (isMuted) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.notifications_off_outlined,
                size: 14,
                color: context.textSecondary,
              ),
            ],
          ],
        ),
        subtitle: Text(
          chat.unreadCount > 0
              ? context.t.newMessagesCount(
                  chat.unreadCount,
                  chat.unreadCount == 1
                      ? context.t.message
                      : context.t.messages)
              : preview,
          style: TextStyle(color: context.textSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: chat.unreadCount > 0
            ? _UnreadCountBadge(count: chat.unreadCount)
            : null,
      ),
    );
  }
}

class _GlassChatCard extends StatelessWidget {
  final Widget child;
  final bool emphasize;

  const _GlassChatCard({required this.child, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    // Backdrop blur + soft uniform surface + thin hairline border +
    // shadow stack. The top sheen was dropped to remove the reflection
    // that read as harsh on light backgrounds. Sigma bumped to 22 for
    // a softer, more diffused blur.
    final isDark = context.isDark;
    final surfaceColor = isDark
        ? const Color(0xFF1E1E2C).withValues(alpha: 0.50)
        : Colors.white.withValues(alpha: 0.40);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.45);
    final outerShadow = isDark
        ? Colors.black.withValues(alpha: 0.14)
        : const Color(0xFF0A1B3D).withValues(alpha: 0.07);
    final emphasizeShadow =
        AppColors.purple.withValues(alpha: isDark ? 0.20 : 0.10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: outerShadow,
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            if (emphasize)
              BoxShadow(
                color: emphasizeShadow,
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
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
