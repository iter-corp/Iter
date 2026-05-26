import 'package:flutter/material.dart';
// ignore: unnecessary_import — Clipboard/ClipboardData come from services.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import '../user_screen.dart';
import 'admin_reports_toolbar.dart';

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
          title: Text(context.t.adminProfileReports),
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
                      title: Text(context.t.adminClearResolvedTitle),
                      content: Text(
                        context.t.adminClearResolvedBody(resolved.length),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(context.t.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(context.t.clear),
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
                  AppFeedback.showSuccess(
                      context, context.t.adminResolvedReportsCleared);
                },
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text(context.t.adminClearResolved),
              ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            tabs: [
              Tab(text: context.t.adminTabOpen(unresolved.length)),
              Tab(text: context.t.adminTabResolved(resolved.length)),
            ],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (_) => TabBarView(
            children: [
              _ReportsList(
                reports: unresolved,
                emptyTitle: all.isEmpty
                    ? context.t.adminNoProfileReports
                    : context.t.adminNoOpenReports,
                emptySubtitle: context.t.adminFreshReportsHere,
              ),
              _ReportsList(
                reports: resolved,
                emptyTitle: context.t.adminNothingResolvedYet,
                emptySubtitle: context.t.adminClosedReportsMoveHere,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stateful list with shared toolbar (search + bulk-delete). See
/// admin_post_reports_screen.dart for the rationale.
class _ReportsList extends ConsumerStatefulWidget {
  final List<UserProfileReport> reports;
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

  List<UserProfileReport> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.reports;
    return widget.reports.where((r) {
      final hay = [
        r.targetUsername,
        r.targetUid,
        r.reporterUsername,
        r.reporterUid,
        r.reason,
        r.details ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final admin = ref.read(adminServiceProvider);
    try {
      await Future.wait(
          ids.map((id) => admin.deleteUserProfileReport(id)));
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
                        Icon(Icons.flag_outlined,
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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final r = visible[i];
                    return _ReportTile(
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReportTile extends ConsumerWidget {
  final UserProfileReport report;
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

  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  String _fullTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    return DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(l);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selecting) {
      final title = report.targetUsername.isEmpty
          ? report.targetUid
          : report.targetUsername;
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          subtitle: Text(
            '${report.reason} · ${report.reporterUsername.isEmpty ? report.reporterUid : report.reporterUsername}',
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
            report.resolved ? Icons.check_circle_outline : Icons.flag_outlined,
            color: report.resolved ? Colors.green : const Color(0xFFE04E5C),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.t.copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: 'When: ${_fullTime(report.createdAt)}\n'
                        'Reason: ${report.reason}\n'
                        'Reported user: ${report.targetUsername.isEmpty ? report.targetUid : "${report.targetUsername} (${report.targetUid})"}\n'
                        'Reporter: ${report.reporterUsername.isEmpty ? report.reporterUid : "${report.reporterUsername} (${report.reporterUid})"}\n\n'
                        'Details: ${(report.details ?? "").trim()}',
                  ));
                  AppFeedback.showInfo(
                      context, context.t.adminCopiedToClipboard);
                },
              ),
              Icon(Icons.expand_more, color: context.textSecondary),
            ],
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
              context.t.adminReportedProfile,
              report.targetUsername.isEmpty
                  ? report.targetUid
                  : '${report.targetUsername} (${report.targetUid})',
            ),
            _kv(
                context,
                context.t.adminReporter,
                report.reporterUsername.isEmpty
                    ? report.reporterUid
                    : '${report.reporterUsername} (${report.reporterUid})'),
            _kv(context, context.t.adminReason, report.reason),
            _kv(context, context.t.adminWhen, _fullTime(report.createdAt)),
            if ((report.details ?? '').trim().isNotEmpty)
              _kv(context, context.t.adminDetails, report.details!.trim()),
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
                  child: Text(report.resolved
                      ? context.t.adminReopen
                      : context.t.adminMarkResolved),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(uid: report.targetUid),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.t.adminViewProfile),
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
                        title: Text(context.t.adminRemoveUserTitle),
                        content: Text(context.t.adminRemoveUserBody),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(context.t.cancel),
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
                              AppFeedback.showSuccess(
                                  context, context.t.adminUserRemoved);
                            },
                            child: Text(context.t.adminRemoveUser),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(context.t.adminRemoveUser),
                ),
                IconButton(
                  tooltip: 'Delete report',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete report?'),
                        content: const Text(
                          'This will remove this report without taking any action on the user.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref
                          .read(adminServiceProvider)
                          .deleteUserProfileReport(report.id);
                      if (!context.mounted) return;
                      AppFeedback.showSuccess(context, 'Report deleted');
                    } catch (e) {
                      if (!context.mounted) return;
                      AppFeedback.showError(context, 'Failed: $e');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
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
