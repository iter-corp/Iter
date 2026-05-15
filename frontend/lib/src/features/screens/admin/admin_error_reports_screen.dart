import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/admin_providers.dart';
import '../../../services/error_report_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';

/// Admin view of app-wide errors captured by [ErrorReportService] — uncaught
/// Flutter / zone / platform errors plus anything reported manually. Lets the
/// admin scan failures, mark them resolved, and clear the list.
class AdminErrorReportsScreen extends ConsumerStatefulWidget {
  const AdminErrorReportsScreen({super.key});

  @override
  ConsumerState<AdminErrorReportsScreen> createState() =>
      _AdminErrorReportsScreenState();
}

class _AdminErrorReportsScreenState
    extends ConsumerState<AdminErrorReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(errorReportsProvider);
    final all = reportsAsync.valueOrNull ?? const <ErrorReport>[];
    final unsolved = all.where((r) => !r.resolved).toList();
    final solved = all.where((r) => r.resolved).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.surfaceSoft,
        appBar: AppBar(
          title: const Text('Error reports'),
          backgroundColor: context.cardBg,
          foregroundColor: context.textPrimary,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'clear_resolved') {
                  final messenger = ScaffoldMessenger.of(context);
                  final n =
                      await ref.read(errorReportAdminProvider).clearResolved();
                  AppFeedback.showInfoOn(
                      messenger, 'Cleared $n solved report(s)');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clear_resolved',
                  child: Text('Clear all solved reports'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            tabs: [
              Tab(text: 'Unsolved (${unsolved.length})'),
              Tab(text: 'Solved (${solved.length})'),
            ],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (_) => TabBarView(
            children: [
              _ReportsList(
                reports: unsolved,
                emptyTitle:
                    all.isEmpty ? 'No error reports' : 'No unsolved errors 🎉',
                emptySubtitle: 'Captured app errors will appear here.',
              ),
              _ReportsList(
                reports: solved,
                emptyTitle: 'Nothing solved yet',
                emptySubtitle: 'Reports you mark as solved move here.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  final List<ErrorReport> reports;
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
              Icon(Icons.check_circle_outline,
                  size: 48, color: context.textMuted),
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
    // Lightweight rollup: top recurring messages within this tab.
    final counts = <String, int>{};
    for (final r in reports) {
      final key = r.message.split('\n').first.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final topRepeated = counts.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (topRepeated.isNotEmpty) ...[
          _RollupCard(entries: topRepeated.take(5).toList()),
          const SizedBox(height: 12),
        ],
        ...reports.map((r) => _ReportTile(report: r)),
      ],
    );
  }
}

class _RollupCard extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  const _RollupCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  size: 16, color: AppColors.purple),
              const SizedBox(width: 6),
              Text(
                'Most frequent (current list)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${e.value}×',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12.5, color: context.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends ConsumerWidget {
  final ErrorReport report;
  const _ReportTile({required this.report});

  // Short form for the collapsed row.
  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  // Full date + time for the expanded detail.
  String _fullTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    final stamp = DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(l);
    return '$stamp  (${_ago(l)})';
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${(d.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = (report.screen ?? '').trim().isEmpty
        ? 'Unknown screen'
        : report.screen!.trim();
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
            report.resolved
                ? Icons.check_circle_outline
                : Icons.error_outline_rounded,
            color: report.resolved ? Colors.green : const Color(0xFFE04E5C),
          ),
          title: Text(
            report.message.split('\n').first,
            maxLines: 2,
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
                _pill(context, Icons.layers_outlined, screen),
                _pill(context, Icons.schedule, _shortTime(report.createdAt)),
                _pill(context, Icons.devices_other,
                    report.platform.isEmpty ? '?' : report.platform),
              ],
            ),
          ),
          children: [
            // Full structured details.
            _kv(context, 'When', _fullTime(report.createdAt)),
            _kv(context, 'Page / screen', screen),
            _kv(context, 'Type', report.kind),
            _kv(context, 'Platform',
                report.platform.isEmpty ? '—' : report.platform),
            _kv(context, 'App version',
                report.appVersion.isEmpty ? '—' : report.appVersion),
            _kv(
                context,
                'User',
                (report.uid ?? '').trim().isEmpty
                    ? 'not signed in'
                    : report.uid!.trim()),
            if (report.context != null && report.context!.trim().isNotEmpty)
              _kv(context, 'Context', report.context!.trim()),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Error message',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              report.message,
              style: TextStyle(fontSize: 12.5, color: context.textPrimary),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Stack trace',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                report.stack.isEmpty ? '(no stack)' : report.stack,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: 'When: ${_fullTime(report.createdAt)}\n'
                          'Screen: $screen\n'
                          'Type: ${report.kind} · ${report.platform} · v${report.appVersion}\n'
                          'User: ${report.uid ?? "not signed in"}\n\n'
                          '${report.message}\n\n${report.stack}',
                    ));
                    AppFeedback.showInfo(context, 'Copied to clipboard');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref
                      .read(errorReportAdminProvider)
                      .setResolved(report.id, !report.resolved),
                  child: Text(report.resolved ? 'Reopen' : 'Mark resolved'),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: () =>
                      ref.read(errorReportAdminProvider).delete(report.id),
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
              width: 96,
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
