import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../theme/app_theme.dart';
import '../screens/create_post_screen.dart';
import '../widgets/primary_action_button.dart';

class DesktopNavSidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final int unreadChats;
  final bool isCompact;

  const DesktopNavSidebar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.unreadChats,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
    final authUser = ref.watch(authStateProvider).valueOrNull;

    final displayName = userDoc?['username'] as String? ??
        userDoc?['email'] as String? ??
        authUser?.displayName ??
        authUser?.email?.split('@').first ??
        'User';
    final handle = userDoc?['handle'] as String? ??
        (authUser?.email != null ? '@${authUser!.email!.split('@').first}' : '@user');
    final avatarUrl = userDoc?['avatarUrl'] as String? ?? authUser?.photoURL;

    final navItems = [
      _NavItemData(icon: Icons.home_rounded, label: context.t.home, index: 0),
      _NavItemData(icon: Icons.calendar_month_rounded, label: context.t.event, index: 1),
      _NavItemData(icon: Icons.explore_rounded, label: 'Explore', index: 2),
      _NavItemData(
        icon: Icons.chat_bubble_outline_rounded,
        label: context.t.message,
        index: 3,
        badgeCount: unreadChats,
      ),
      _NavItemData(icon: Icons.person_rounded, label: context.t.profile, index: 4),
    ];

    final sidebarWidth = isCompact ? 76.0 : 250.0;

    return Container(
      width: sidebarWidth,
      height: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 16,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C0F17) : const Color(0xFFF7F8FA),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          // ── App Brand Header ──
          if (isCompact)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildBrandLogo(context),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _buildBrandLogo(context),
                  const SizedBox(width: 12),
                  Text(
                    context.t.headerAppTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // ── Navigation Items ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...navItems.map((item) => _buildNavTile(context, item)),
                const SizedBox(height: 20),

                // ── "+ Post" Action Button ──
                if (isCompact)
                  Center(
                    child: Tooltip(
                      message: context.t.post,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFCE5DE5), Color(0xFF7A3FB8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7A3FB8).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const CreatePostScreen()),
                              );
                              ref.invalidate(feedProvider);
                            },
                            child: const Center(
                              child: Icon(Icons.add_rounded,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  PrimaryActionButton(
                    label: context.t.post,
                    icon: Icons.add_rounded,
                    fullWidth: true,
                    size: PrimaryActionSize.large,
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreatePostScreen()),
                      );
                      ref.invalidate(feedProvider);
                    },
                  ),
              ],
            ),
          ),

          // ── Bottom User Profile Pill / Avatar ──
          if (isCompact)
            _buildCompactUserAvatar(
                context, ref, displayName, handle, avatarUrl, isDark)
          else
            _buildUserCard(context, ref, displayName, handle, avatarUrl, isDark),
        ],
      ),
    );
  }

  Widget _buildBrandLogo(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7A3FB8).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.asset(
          'assets/img/app_icon.png',
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/icons/app_icon.png',
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFCE5DE5), Color(0xFF7A3FB8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.public_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile(BuildContext context, _NavItemData item) {
    final isSelected = selectedIndex == item.index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tooltip(
          message: item.label,
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => onTabSelected(item.index),
              borderRadius: BorderRadius.circular(14),
              hoverColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? const Color(0xFF7A3FB8).withValues(alpha: 0.22)
                          : const Color(0xFF7A3FB8).withValues(alpha: 0.12))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(
                          color: const Color(0xFFCE5DE5).withValues(alpha: 0.4),
                          width: 1,
                        )
                      : Border.all(color: Colors.transparent, width: 1),
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: isSelected
                            ? const Color(0xFFCE5DE5)
                            : context.textMuted,
                      ),
                      if (item.badgeCount != null && item.badgeCount! > 0)
                        Positioned(
                          top: -3,
                          right: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => onTabSelected(item.index),
          borderRadius: BorderRadius.circular(14),
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? const Color(0xFF7A3FB8).withValues(alpha: 0.22)
                      : const Color(0xFF7A3FB8).withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(
                      color: const Color(0xFFCE5DE5).withValues(alpha: 0.4),
                      width: 1,
                    )
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: isSelected
                      ? const Color(0xFFCE5DE5)
                      : context.textMuted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? context.textPrimary
                          : context.textMuted,
                    ),
                  ),
                ),
                if (item.badgeCount != null && item.badgeCount! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${item.badgeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactUserAvatar(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String handle,
    String? avatarUrl,
    bool isDark,
  ) {
    return Center(
      child: PopupMenuButton<String>(
        tooltip: displayName,
        offset: const Offset(50, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (val) {
          if (val == 'signout') {
            ref.read(authServiceProvider).signOut();
          } else if (val == 'profile') {
            onTabSelected(4);
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'profile',
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 8),
                Text(context.t.profile),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'signout',
            child: Row(
              children: [
                const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text(context.t.logout,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ],
        child: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF7A3FB8).withValues(alpha: 0.3),
          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
              ? CachedNetworkImageProvider(avatarUrl)
              : null,
          child: (avatarUrl == null || avatarUrl.isEmpty)
              ? Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String handle,
    String? avatarUrl,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF7A3FB8).withValues(alpha: 0.3),
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, size: 20, color: context.textMuted),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'signout') {
                ref.read(authServiceProvider).signOut();
              } else if (val == 'profile') {
                onTabSelected(4);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 8),
                    Text(context.t.profile),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded,
                        size: 18, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(context.t.logout,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final int index;
  final int? badgeCount;

  _NavItemData({
    required this.icon,
    required this.label,
    required this.index,
    this.badgeCount,
  });
}
