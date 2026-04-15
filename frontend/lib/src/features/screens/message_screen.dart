import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          otherName: conv.otherUsername,
          otherAvatar: conv.otherAvatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acceptedInboxAsync = ref.watch(acceptedInboxProvider);
    final requestsAsync = ref.watch(requestsProvider);
    final allConvs =
        (acceptedInboxAsync.value ?? []).where(_matches).toList();
    final requestConvs =
        (requestsAsync.value ?? []).where(_matches).toList();

    return SafeArea(
      child: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

          // ── Tab bar ─────────────────────────────────────────────────
          MessageTabBar(
            selectedTab: selectedTab,
            allCount: allConvs.length,
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
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: conv.otherAvatarUrl.isNotEmpty
            ? NetworkImage(conv.otherAvatarUrl)
            : null,
        child: conv.otherAvatarUrl.isEmpty
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        conv.otherUsername,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
