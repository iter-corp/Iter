import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import 'chat_screen.dart';

class HiddenRequestsScreen extends StatelessWidget {
  final List<ChatConversation> requests;

  const HiddenRequestsScreen({super.key, required this.requests});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  const Text(
                    "Hidden Requests",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            /// SUBTITLE
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                "Requests containing messages that may be offensive or unwanted are moved to this folder.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),

            const SizedBox(height: 8),

            /// LIST
            Expanded(
              child: ListView.builder(
                itemCount: requests.length,
                itemBuilder: (context, i) {
                  final msg = requests[i];
                  return ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: msg.chatId,
                          otherUid: msg.otherUid,
                          otherName: msg.otherUsername,
                          otherAvatar: msg.otherAvatarUrl,
                        ),
                      ),
                    ),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: msg.otherAvatarUrl.isNotEmpty
                          ? NetworkImage(msg.otherAvatarUrl)
                          : null,
                      child: msg.otherAvatarUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    title: Text(
                      msg.otherUsername,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      msg.lastMessage,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: msg.unreadCount > 0
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// REQUESTS TAB CONTENT
class RequestsTab extends StatelessWidget {
  final List<ChatConversation> requests;
  final Function(ChatConversation) onTap;

  const RequestsTab({
    super.key,
    required this.requests,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        /// HIDDEN REQUESTS ROW
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications_off_outlined, size: 24),
          ),
          title: const Text("Hidden Requests",
              style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HiddenRequestsScreen(requests: requests),
            ),
          ),
        ),

        const Divider(),

        /// REQUEST LIST
        Expanded(
          child: ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, i) {
              final msg = requests[i];
              return ListTile(
                onTap: () => onTap(msg),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: msg.otherAvatarUrl.isNotEmpty
                      ? NetworkImage(msg.otherAvatarUrl)
                      : null,
                  child: msg.otherAvatarUrl.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                title: Text(
                  msg.otherUsername,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  msg.lastMessage,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: msg.unreadCount > 0
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
            },
          ),
        ),
      ],
    );
  }
}
