import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';

/// TAB BAR
class MessageTabBar extends StatelessWidget {
  final int selectedTab;
  final int allCount;
  final int requestCount;
  final Function(int) onTap;

  const MessageTabBar({
    super.key,
    required this.selectedTab,
    required this.allCount,
    required this.requestCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _tab(context, "All $allCount", 0)),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, "Requests $requestCount", 1)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, int index) {
    final bool isActive = selectedTab == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFB05ECC) : context.inputFill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : context.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// MESSAGE TILE
class MessageTile extends ConsumerWidget {
  final ChatConversation message;
  final VoidCallback onTap;

  const MessageTile({
    super.key,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userByUidProvider(message.otherUid)).value;
    final avatarUrl = userData?['avatarUrl'] as String?;
    final username = userData?['username'] as String? ?? message.otherUsername;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: context.inputFill,
        backgroundImage: avatarUrl != null
            ? CachedNetworkImageProvider(avatarUrl)
            : null,
        child: avatarUrl == null
            ? Icon(Icons.person, color: context.textMuted)
            : null,
      ),
      title: Text(
        username,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        message.lastMessage,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: message.unreadCount > 0
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
