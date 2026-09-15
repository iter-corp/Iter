import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';

class HiddenRequestsScreen extends StatelessWidget {
  final List<ChatConversation> requests;

  const HiddenRequestsScreen({super.key, required this.requests});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cardBg,
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
                  Text(
                    context.t.requestHiddenRequests,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            /// SUBTITLE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                context.t.requestHiddenRequestsSubtitle,
                style: TextStyle(color: context.textSecondary, fontSize: 13),
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
                    leading: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openUserProfile(context, uid: msg.otherUid),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: context.inputFill,
                        backgroundImage: msg.otherAvatarUrl.isNotEmpty
                            ? NetworkImage(msg.otherAvatarUrl)
                            : null,
                        child: msg.otherAvatarUrl.isEmpty
                            ? Icon(Icons.person, color: context.textMuted)
                            : null,
                      ),
                    ),
                    title: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openUserProfile(context, uid: msg.otherUid),
                      child: Text(
                        msg.otherUsername,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    subtitle: Text(
                      msg.unreadCount > 0
                          ? context.t.newMessagesCount(
                              msg.unreadCount,
                              msg.unreadCount == 1
                                  ? context.t.message
                                  : context.t.messages)
                          : msg.lastMessage,
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    trailing: msg.unreadCount > 0
                        ? _UnreadCountBadge(count: msg.unreadCount)
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
    if (requests.isEmpty) {
      return Center(
        child: Text(
          context.t.requestNoRequestsYet,
          style: TextStyle(color: context.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        /// REQUEST LIST
        Expanded(
          child: ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, i) {
              final msg = requests[i];
              return ListTile(
                onTap: () => onTap(msg),
                leading: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openUserProfile(context, uid: msg.otherUid),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: context.inputFill,
                    backgroundImage: msg.otherAvatarUrl.isNotEmpty
                        ? NetworkImage(msg.otherAvatarUrl)
                        : null,
                    child: msg.otherAvatarUrl.isEmpty
                        ? Icon(Icons.person, color: context.textMuted)
                        : null,
                  ),
                ),
                title: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openUserProfile(context, uid: msg.otherUid),
                  child: Text(
                    msg.otherUsername,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                subtitle: Text(
                  msg.unreadCount > 0
                      ? context.t.newMessagesCount(
                          msg.unreadCount,
                          msg.unreadCount == 1
                              ? context.t.message
                              : context.t.messages)
                      : msg.lastMessage,
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
                trailing: msg.unreadCount > 0
                    ? _UnreadCountBadge(count: msg.unreadCount)
                    : null,
              );
            },
          ),
        ),
      ],
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
