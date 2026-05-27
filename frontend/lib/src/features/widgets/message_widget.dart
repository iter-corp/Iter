import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          const padding = 4.0;
          final innerWidth = constraints.maxWidth - padding * 2;
          final pillWidth = innerWidth / 2;
          final isAll = selectedTab == 0;

          return Container(
            height: 48,
            padding: const EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: context.borderColor),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: isAll
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.centerEnd,
                  child: Container(
                    width: pillWidth,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.purple, AppColors.purpleVivid],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purple.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _tab(
                        context,
                        context.t.allCount(allCount),
                        Icons.chat_bubble_rounded,
                        0,
                      ),
                    ),
                    Expanded(
                      child: _tab(
                        context,
                        context.t.requestsCount(requestCount),
                        Icons.mark_chat_unread_rounded,
                        1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tab(BuildContext context, String label, IconData icon, int index) {
    final bool isActive = selectedTab == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            color: isActive ? Colors.white : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isActive ? Colors.white : context.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
        backgroundImage:
            avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
        child: avatarUrl == null
            ? Icon(Icons.person, color: context.textMuted)
            : null,
      ),
      title: Text(
        username,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        message.unreadCount > 0
            ? context.t.newMessagesCount(
                message.unreadCount,
                message.unreadCount == 1
                    ? context.t.message
                    : context.t.messages)
            : message.lastMessage,
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: message.unreadCount > 0
          ? _UnreadCountBadge(count: message.unreadCount)
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
