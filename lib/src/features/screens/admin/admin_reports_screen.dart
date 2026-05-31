import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_report_notifications_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';
import 'admin_comment_reports_screen.dart';
import 'admin_discuss_reports_screen.dart';
import 'admin_error_reports_screen.dart';
import 'admin_post_reports_screen.dart';
import 'admin_user_reports_screen.dart';

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNewPostReports = ref.watch(hasNewPostReportsProvider);
    final hasNewDiscussReports = ref.watch(hasNewDiscussReportsProvider);
    final hasNewProfileReports = ref.watch(hasNewProfileReportsProvider);
    final hasNewCommentReports = ref.watch(hasNewCommentReportsProvider);
    final hasNewErrorReports = ref.watch(hasNewErrorReportsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.reports),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
          _ReportsTile(
            icon: Icons.flag_outlined,
            title: context.t.adminPostReports,
            subtitle: context.t.adminPostReportsSubtitle,
            color: const Color(0xFFE04E5C),
            showNotificationDot: hasNewPostReports,
            onTap: () {
              ref.read(adminReportSeenProvider.notifier).markPostReportsSeen();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminPostReportsScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportsTile(
            icon: Icons.forum_outlined,
            title: context.t.adminDiscussReports,
            subtitle: context.t.adminDiscussReportsSubtitle,
            color: const Color(0xFFD044E8),
            showNotificationDot: hasNewDiscussReports,
            onTap: () {
              ref
                  .read(adminReportSeenProvider.notifier)
                  .markDiscussReportsSeen();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminDiscussReportsScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportsTile(
            icon: Icons.person_search_outlined,
            title: context.t.adminProfileReports,
            subtitle: context.t.adminProfileReportsSubtitle,
            color: const Color(0xFFDE5D83),
            showNotificationDot: hasNewProfileReports,
            onTap: () {
              ref
                  .read(adminReportSeenProvider.notifier)
                  .markProfileReportsSeen();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminUserReportsScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportsTile(
            icon: Icons.mode_comment_outlined,
            title: context.t.adminCommentReports,
            subtitle: context.t.adminCommentReportsSubtitle,
            color: const Color(0xFF9C6ADE),
            showNotificationDot: hasNewCommentReports,
            onTap: () {
              ref
                  .read(adminReportSeenProvider.notifier)
                  .markCommentReportsSeen();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminCommentReportsScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ReportsTile(
            icon: Icons.bug_report_outlined,
            title: context.t.errorReports,
            subtitle: context.t.adminErrorReportsSubtitle,
            color: const Color(0xFFE04E5C),
            showNotificationDot: hasNewErrorReports,
            onTap: () {
              ref.read(adminReportSeenProvider.notifier).markErrorReportsSeen();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminErrorReportsScreen()),
              );
            },
          ),
          ],
        ),
      ),
    );
  }
}

class _ReportsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool showNotificationDot;
  final VoidCallback onTap;

  const _ReportsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.showNotificationDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      radius: 16,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                            border: Border.all(color: Colors.white, width: 1.2),
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
      ),
    );
  }
}
