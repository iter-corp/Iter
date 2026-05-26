import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../services/error_report_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import 'admin_reports_toolbar.dart';

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
          title: Text(context.t.errorReports),
          backgroundColor: context.cardBg,
          foregroundColor: context.textPrimary,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'clear_resolved') {
                  final messenger = ScaffoldMessenger.of(context);
                  final t = context.t;
                  final n =
                      await ref.read(errorReportAdminProvider).clearResolved();
                  AppFeedback.showInfoOn(
                      messenger, t.adminClearedSolvedReports(n));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear_resolved',
                  child: Text(context.t.adminClearAllSolvedReports),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            tabs: [
              Tab(text: context.t.adminTabUnsolved(unsolved.length)),
              Tab(text: context.t.adminTabSolved(solved.length)),
            ],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (_) => TabBarView(
            children: [
              _ReportsList(
                reports: unsolved,
                emptyTitle: all.isEmpty
                    ? context.t.adminNoErrorReports
                    : context.t.adminNoUnsolvedErrors,
                emptySubtitle: context.t.adminCapturedErrorsHere,
              ),
              _ReportsList(
                reports: solved,
                emptyTitle: context.t.adminNothingSolvedYet,
                emptySubtitle: context.t.adminSolvedReportsMoveHere,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stateful list with shared toolbar (search + bulk-delete). Wraps the
/// rollup card + per-report tiles so admins can search the long error
/// stream and bulk-clear noise. See admin_post_reports_screen.dart for
/// the toolbar pattern.
class _ReportsList extends ConsumerStatefulWidget {
  final List<ErrorReport> reports;
  final String emptyTitle;
  final String emptySubtitle;
  const _ReportsList({
    required this.reports,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  @override
  ConsumerState<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends ConsumerState<_ReportsList> {
  final ReportsToolbarController _toolbar = ReportsToolbarController.create();
  String _query = '';
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _toolbar.dispose();
    super.dispose();
  }

  List<ErrorReport> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.reports;
    return widget.reports.where((r) {
      final hay = [
        r.message,
        r.kind,
        r.context ?? '',
        r.screen ?? '',
        r.platform,
        r.appVersion,
        r.uid ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final svc = ref.read(errorReportAdminProvider);
    try {
      await Future.wait(ids.map((id) => svc.delete(id)));
      if (!mounted) return;
      AppFeedback.showSuccess(context, context.t.adminReportDeleted);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, context.t.adminActionFailed(e));
    } finally {
      if (mounted) {
        setState(_selectedIds.clear);
        _toolbar.exitSelectionMode();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered;

    // Rollup is computed from the visible set so it stays relevant when
    // the admin narrows the list with a search.
    final counts = <String, int>{};
    for (final r in visible) {
      final key = r.message.split('\n').first.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final topRepeated = counts.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        ReportsToolbar(
          controller: _toolbar,
          selectedCount: _selectedIds.length,
          visibleCount: visible.length,
          onQueryChanged: (v) => setState(() => _query = v),
          onSelectAll: () => setState(() {
            _selectedIds
              ..clear()
              ..addAll(visible.map((r) => r.id));
          }),
          onClearSelection: () => setState(_selectedIds.clear),
          onDeleteSelected: () => _deleteByIds(_selectedIds.toList()),
          onDeleteAll: () => _deleteByIds(visible.map((r) => r.id).toList()),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 48, color: context.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          widget.reports.isEmpty
                              ? widget.emptyTitle
                              : context.t.adminNoResults,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.emptySubtitle,
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    if (topRepeated.isNotEmpty && !_toolbar.isSelecting) ...[
                      _RollupCard(entries: topRepeated.take(5).toList()),
                      const SizedBox(height: 12),
                    ],
                    ...visible.map(
                      (r) => _ReportTile(
                        report: r,
                        selecting: _toolbar.isSelecting,
                        selected: _selectedIds.contains(r.id),
                        onSelectedChanged: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedIds.add(r.id);
                            } else {
                              _selectedIds.remove(r.id);
                            }
                          });
                        },
                        onLongPress: () {
                          if (!_toolbar.isSelecting) {
                            _toolbar.enterSelectionMode();
                            setState(() => _selectedIds.add(r.id));
                          }
                        },
                      ),
                    ),
                  ],
                ),
        ),
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
                context.t.adminMostFrequent,
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
  final bool selecting;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onLongPress;

  const _ReportTile({
    required this.report,
    this.selecting = false,
    this.selected = false,
    required this.onSelectedChanged,
    required this.onLongPress,
  });

  // Short form for the collapsed row.
  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  // Full date + time for the expanded detail.
  String _fullTime(BuildContext context, DateTime? dt) {
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    final stamp = DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(l);
    return '$stamp  (${context.t.timeAgo(l)})';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = (report.screen ?? '').trim().isEmpty
        ? context.t.adminUnknownScreen
        : report.screen!.trim();
    if (selecting) {
      final title = report.message.split('\n').first;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF7E3BE8) : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: CheckboxListTile(
          value: selected,
          onChanged: (v) => onSelectedChanged(v ?? false),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          subtitle: Text(
            '${report.kind} · $screen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          activeColor: const Color(0xFF7E3BE8),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      );
    }
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
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
          // Trailing chevron is replaced with a row: a copy button (so
          // admins can grab the full report without expanding) plus the
          // expansion arrow ExpansionTile draws by default isn't
          // configurable. We use a custom `trailing` to host both.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.t.copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copyReportDetails(context, screen),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
              ),
              Icon(Icons.expand_more, color: context.textSecondary),
            ],
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
            _kv(context, context.t.adminWhen,
                _fullTime(context, report.createdAt)),
            _kv(context, context.t.adminPageScreen, screen),
            _kv(context, context.t.adminType, report.kind),
            _kv(context, context.t.adminPlatform,
                report.platform.isEmpty ? '—' : report.platform),
            _kv(context, context.t.adminAppVersionLabel,
                report.appVersion.isEmpty ? '—' : report.appVersion),
            _kv(
                context,
                context.t.user,
                (report.uid ?? '').trim().isEmpty
                    ? context.t.adminNotSignedIn
                    : report.uid!.trim()),
            if (report.context != null && report.context!.trim().isNotEmpty)
              _kv(context, context.t.adminContext, report.context!.trim()),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.t.adminErrorMessage,
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
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.t.adminStackTrace,
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
                report.stack.isEmpty ? context.t.adminNoStack : report.stack,
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
                      text: 'When: ${_fullTime(context, report.createdAt)}\n'
                          'Screen: $screen\n'
                          'Type: ${report.kind} · ${report.platform} · v${report.appVersion}\n'
                          'User: ${report.uid ?? "not signed in"}\n\n'
                          '${report.message}\n\n${report.stack}',
                    ));
                    AppFeedback.showInfo(context, context.t.adminCopiedToClipboard);
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(context.t.copy),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref
                      .read(errorReportAdminProvider)
                      .setResolved(report.id, !report.resolved),
                  child: Text(report.resolved
                      ? context.t.adminReopen
                      : context.t.adminMarkResolved),
                ),
                IconButton(
                  tooltip: context.t.delete,
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
      ),
    );
  }

  /// Copies a fully formatted dump of this error report to the clipboard
  /// (timestamp + screen + version + uid + message + stack). Same payload
  /// the existing Copy button inside the expanded view emits, lifted into
  /// a helper so the header copy icon can reuse it.
  void _copyReportDetails(BuildContext context, String screen) {
    Clipboard.setData(ClipboardData(
      text: 'When: ${_fullTime(context, report.createdAt)}\n'
          'Screen: $screen\n'
          'Type: ${report.kind} · ${report.platform} · v${report.appVersion}\n'
          'User: ${report.uid ?? "not signed in"}\n\n'
          '${report.message}\n\n${report.stack}',
    ));
    AppFeedback.showInfo(context, context.t.adminCopiedToClipboard);
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
