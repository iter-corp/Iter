import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import '../user_screen.dart';

class AdminUserReportsScreen extends ConsumerWidget {
  const AdminUserReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(userProfileReportsProvider);
    final all = reportsAsync.valueOrNull ?? const <UserProfileReport>[];
    final unresolved = all.where((r) => !r.resolved).toList();
    final resolved = all.where((r) => r.resolved).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.surfaceSoft,
        appBar: AppBar(
          title: const Text('Profile reports'),
          backgroundColor: context.cardBg,
          foregroundColor: context.textPrimary,
          elevation: 0,
          actions: [
            if (resolved.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear resolved reports?'),
                      content: Text(
                        'This will delete ${resolved.length} resolved report(s).',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;

                  await Future.wait(
                    resolved
                        .map((r) => ref
                            .read(adminServiceProvider)
                            .deleteUserProfileReport(r.id))
                        .toList(),
                  );
                  if (!context.mounted) return;
                  AppFeedback.showSuccess(context, 'Resolved reports cleared');
                },
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Clear resolved'),
              ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            tabs: [
              Tab(text: 'Open (${unresolved.length})'),
              Tab(text: 'Resolved (${resolved.length})'),
            ],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (_) => TabBarView(
            children: [
              _ReportsList(
                reports: unresolved,
                emptyTitle:
                    all.isEmpty ? 'No profile reports' : 'No open reports',
                emptySubtitle: 'Fresh reports from users will show here.',
              ),
              _ReportsList(
                reports: resolved,
                emptyTitle: 'Nothing resolved yet',
                emptySubtitle: 'Closed reports move here.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  final List<UserProfileReport> reports;
  final String emptyTitle;
  final String emptySubtitle;

  const _ReportsList({
    required this.reports,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined, size: 48, color: context.textMuted),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: reports.length,
      itemBuilder: (_, i) => _ReportTile(report: reports[i]),
    );
  }
}

class _ReportTile extends ConsumerWidget {
  final UserProfileReport report;

  const _ReportTile({required this.report});

  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  String _fullTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    return DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(l);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: report.resolved
              ? context.borderColor
              : const Color(0xFFE04E5C).withValues(alpha: 0.4),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            report.resolved ? Icons.check_circle_outline : Icons.flag_outlined,
            color: report.resolved ? Colors.green : const Color(0xFFE04E5C),
          ),
          title: Text(
            report.targetUsername.isEmpty
                ? report.targetUid
                : report.targetUsername,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              decoration: report.resolved ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _pill(context, Icons.report_outlined, report.reason),
                _pill(
                    context,
                    Icons.person_outline,
                    report.reporterUsername.isEmpty
                        ? report.reporterUid
                        : report.reporterUsername),
                _pill(context, Icons.schedule, _shortTime(report.createdAt)),
              ],
            ),
          ),
          children: [
            _kv(
              context,
              'Reported profile',
              report.targetUsername.isEmpty
                  ? report.targetUid
                  : '${report.targetUsername} (${report.targetUid})',
            ),
            _kv(
                context,
                'Reporter',
                report.reporterUsername.isEmpty
                    ? report.reporterUid
                    : '${report.reporterUsername} (${report.reporterUid})'),
            _kv(context, 'Reason', report.reason),
            _kv(context, 'When', _fullTime(report.createdAt)),
            if ((report.details ?? '').trim().isNotEmpty)
              _kv(context, 'Details', report.details!.trim()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(adminServiceProvider)
                      .setUserProfileReportResolved(
                          report.id, !report.resolved),
                  child: Text(report.resolved ? 'Reopen' : 'Mark resolved'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(uid: report.targetUid),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View profile'),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove user?'),
                        content: const Text(
                          'This will permanently remove this user account and their data. This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await ref
                                  .read(adminServiceProvider)
                                  .deleteUser(report.targetUid);
                              await ref
                                  .read(adminServiceProvider)
                                  .deleteUserProfileReport(report.id);
                              if (!context.mounted) return;
                              AppFeedback.showSuccess(context, 'User removed');
                            },
                            child: const Text('Remove user'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Remove user'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: context.textSecondary),
            const SizedBox(width: 3),
            Text(
              text,
              style: TextStyle(fontSize: 10.5, color: context.textSecondary),
            ),
          ],
        ),
      );

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                k,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: TextStyle(fontSize: 12, color: context.textPrimary),
              ),
            ),
          ],
        ),
      );
}
