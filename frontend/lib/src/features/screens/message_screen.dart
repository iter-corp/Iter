import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/chat_providers.dart';
import '../../services/chat_service.dart';
import '../widgets/message_widget.dart';
import 'chat_screen.dart';
import 'request_screen.dart';

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: MessageBody(),
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
<<<<<<< Updated upstream
          otherName: conv.otherUsername,
          otherAvatar: conv.otherAvatarUrl,
=======
          otherName: conv.isGroup ? conv.groupName : conv.otherUsername,
          otherAvatar: conv.isGroup ? conv.groupAvatarUrl : conv.otherAvatarUrl,
>>>>>>> Stashed changes
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acceptedInboxAsync = ref.watch(acceptedInboxProvider);
    final requestsAsync = ref.watch(requestsProvider);
<<<<<<< Updated upstream
    final allConvs = (acceptedInboxAsync.value ?? []).where(_matches).toList();
    final requestConvs = (requestsAsync.value ?? []).where(_matches).toList();
=======
    final eventChatsAsync = ref.watch(myEventChatsProvider);

    final oneToOne =
        (acceptedInboxAsync.valueOrNull ?? []).where(_matches).toList();
    final eventRows =
        (eventChatsAsync.valueOrNull ?? []).where(_matchesEvent).toList();
    final requestConvs =
        (requestsAsync.valueOrNull ?? []).where(_matches).toList();
>>>>>>> Stashed changes

    return SafeArea(
      child: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
<<<<<<< Updated upstream
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey),
                ),
              ),
=======
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        border: InputBorder.none,
                        icon: Icon(Icons.search, color: Colors.grey),
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
>>>>>>> Stashed changes
            ),
          ),

          // ── Tab bar ─────────────────────────────────────────────────
          MessageTabBar(
            selectedTab: selectedTab,
            allCount: allConvs.length,
            requestCount: requestConvs.length,
            onTap: (i) => setState(() => selectedTab = i),
          ),
          const SizedBox(height: 8),

          // ── Info banner for event chats initialization ────────────────
          if (eventChatsAsync.isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF0F7FF),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF0066CC), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Event chats are initializing...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0066CC),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Conversation list ────────────────────────────────────────
          Expanded(
            child: selectedTab == 0
                ? acceptedInboxAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (_) {
                      if (allConvs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: allConvs.length,
                        itemBuilder: (_, i) => _ConvTile(
                          conv: allConvs[i],
                          onTap: () => _openChat(allConvs[i]),
                        ),
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
    return ListTile(
      onTap: onTap,
<<<<<<< Updated upstream
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openUserProfile(context, uid: conv.otherUid),
        child: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: conv.otherAvatarUrl.isNotEmpty
              ? NetworkImage(conv.otherAvatarUrl)
              : null,
          child: conv.otherAvatarUrl.isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : null,
        ),
      ),
      title: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openUserProfile(context, uid: conv.otherUid),
        child: Text(
          conv.otherUsername,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
=======
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
              backgroundColor: Colors.grey.shade200,
              backgroundImage:
                  displayAvatar.isNotEmpty ? NetworkImage(displayAvatar) : null,
              child: displayAvatar.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
>>>>>>> Stashed changes
      ),
      subtitle: Text(
        conv.lastMessage,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
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
          const Icon(Icons.camera_alt_outlined, size: 20, color: Colors.grey),
        ],
      ),
    );
  }
}
