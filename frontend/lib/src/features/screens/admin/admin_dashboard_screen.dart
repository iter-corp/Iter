import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';
import '../../../providers/admin_report_notifications_provider.dart';
import '../../../providers/contact_request_providers.dart';
import '../../../theme/app_theme.dart';
import 'admin_blacklist_screen.dart';
import 'admin_contact_requests_screen.dart';
import 'admin_events_screen.dart';
import 'admin_posts_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final hasNewReports = ref.watch(hasAnyNewReportsProvider);
    final hasUnreadContact = ref.watch(hasUnreadContactRequestsProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'You do not have admin access.',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('Admin dashboard'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          28 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _AdminTile(
            icon: Icons.people_alt_outlined,
            title: 'Users',
            subtitle: 'Search, suspend, promote',
            color: const Color(0xFF7E3BE8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.feed_outlined,
            title: 'Posts',
            subtitle: 'Review and delete posts',
            color: const Color(0xFFD044E8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminPostsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.assessment_outlined,
            title: 'Reports',
            subtitle: 'Post, discuss, profile, and error reports',
            color: const Color(0xFFE04E5C),
            showNotificationDot: hasNewReports,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.support_agent_outlined,
            title: 'Contact requests',
            subtitle: 'Inbox + history of messages and org applications',
            color: AppColors.purple,
            showNotificationDot: hasUnreadContact,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminContactRequestsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.event_outlined,
            title: 'Events',
            subtitle: 'Create / edit / delete events',
            color: const Color(0xFFFF6B35),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminEventsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.block_outlined,
            title: 'Blacklisted emails',
            subtitle: 'Deleted users who cannot re-register',
            color: Colors.red,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminBlacklistScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.settings_outlined,
            title: 'App settings',
            subtitle: 'Feature flags, announcement, store links, maintenance',
            color: const Color(0xFF3AB0FF),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool showNotificationDot;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.showNotificationDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color),
                    if (showNotificationDot)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE04E5C),
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: context.cardBg, width: 1.2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFB1B1B6)),
            ],
          ),
        ),
      ),
    );
  }
}
