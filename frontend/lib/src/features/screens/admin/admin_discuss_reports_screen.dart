import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../model/post_model.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import '../post_detail_screen.dart';
import '../qa_thread_screen.dart';

class AdminDiscussReportsScreen extends ConsumerWidget {
  const AdminDiscussReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(discussReportsProvider);
    final all = reportsAsync.valueOrNull ?? const <PostReport>[];
    final unresolved = all.where((r) => !r.resolved).toList();
    final resolved = all.where((r) => r.resolved).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.surfaceSoft,
        appBar: AppBar(
          title: Text(context.t.adminDiscussReports),
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
                            .deleteDiscussReport(r.id))
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
                    ? context.t.adminNoDiscussReports
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

class _ReportsList extends StatelessWidget {
  final List<PostReport> reports;
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
              Icon(Icons.forum_outlined, size: 48, color: context.textMuted),
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
  final PostReport report;

  const _ReportTile({required this.report});

  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  String _fullTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    return DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(l);
  }

  Future<void> _openReportedThread(BuildContext context) async {
    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(report.postId)
        .get();
    if (!context.mounted) return;

    if (snap.exists) {
      final data = snap.data() ?? {};
      final isQa = (data['postType'] as String?) == 'qa';
      if (isQa) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QaThreadScreen(post: Post.fromDoc(snap)),
          ),
        );
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: report.postId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = report.postCaption.trim().isEmpty
        ? context.t.adminNoQuestionText
        : report.postCaption.trim();
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
            caption,
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
            _kv(context, context.t.adminReportedThread, caption),
            _kv(
                context,
                context.t.adminThreadAuthor,
                report.postAuthorUsername.isEmpty
                    ? report.postAuthorUid
                    : '${report.postAuthorUsername} (${report.postAuthorUid})'),
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
                      .setDiscussReportResolved(report.id, !report.resolved),
                  child: Text(report.resolved
                      ? context.t.adminReopen
                      : context.t.adminMarkResolved),
                ),
                TextButton.icon(
                  onPressed: () => _openReportedThread(context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.t.adminViewThread),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                          report.resolved
                              ? context.t.adminDeleteReportTitle
                              : context.t.adminTakeDownThreadTitle,
                        ),
                        content: Text(
                          report.resolved
                              ? context.t.adminDeleteReportBody
                              : context.t.adminTakeDownThreadBody,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.t.cancel),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              report.resolved
                                  ? context.t.adminDeleteReport
                                  : context.t.adminTakeDownThread,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmed != true) return;

                    try {
                      if (report.resolved) {
                        await ref
                            .read(adminServiceProvider)
                            .deleteDiscussReport(report.id);
                        if (!context.mounted) return;
                        AppFeedback.showSuccess(
                            context, context.t.adminReportDeleted);
                        return;
                      }

                      await ref
                          .read(adminServiceProvider)
                          .deletePost(report.postId);
                      await ref
                          .read(adminServiceProvider)
                          .setDiscussReportResolved(report.id, true);
                      if (!context.mounted) return;
                      AppFeedback.showSuccess(
                        context,
                        context.t.adminThreadTakenDown,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      AppFeedback.showError(
                        context,
                        context.t.adminActionFailed(e),
                      );
                    }
                  },
                  child: Text(
                    report.resolved
                        ? context.t.adminDeleteReport
                        : context.t.adminTakeDownThread,
                  ),
                ),
                if (!report.resolved)
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
                            'This will remove this report without taking any action on the thread.',
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
                            .deleteDiscussReport(report.id);
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
            IconButton(
              tooltip: context.t.copy,
              onPressed: () => Clipboard.setData(ClipboardData(text: v)),
              icon: Icon(Icons.copy_rounded,
                  size: 15, color: context.textSecondary),
            ),
          ],
        ),
      );
}
