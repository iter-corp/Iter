import 'package:flutter/material.dart';

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
class MessageTile extends StatelessWidget {
  final ChatConversation message;
  final VoidCallback onTap;

  const MessageTile({
    super.key,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: context.inputFill,
        backgroundImage: message.otherAvatarUrl.isNotEmpty
            ? NetworkImage(message.otherAvatarUrl)
            : null,
        child: message.otherAvatarUrl.isEmpty
            ? Icon(Icons.person, color: context.textMuted)
            : null,
      ),
      title: Text(
        message.otherUsername,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        message.lastMessage,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.unreadCount > 0)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFB05ECC),
                shape: BoxShape.circle,
              ),
            ),
          Icon(Icons.camera_alt_outlined,
              size: 20, color: context.textSecondary),
        ],
      ),
    );
  }
}
