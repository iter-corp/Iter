import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';
import 'admin_event_registrations_screen.dart';
import 'admin_events_screen.dart';
import 'admin_posts_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have admin access.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Admin dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
            icon: Icons.how_to_reg_outlined,
            title: 'Event registrations',
            subtitle: 'Approve or reject pending registrations',
            color: const Color(0xFF2EBD6B),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminEventRegistrationsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            icon: Icons.settings_outlined,
            title: 'App settings',
            subtitle: 'Feature flags, announcement, maintenance',
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
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEDF2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
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
