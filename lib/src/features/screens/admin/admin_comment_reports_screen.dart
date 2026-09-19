import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../providers/comment_providers.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import '../../widgets/app_page_background.dart';
import '../../widgets/skeleton_loader.dart';
import '../post_detail_screen.dart';

class AdminCommentReportsScreen extends ConsumerWidget {
  const AdminCommentReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(commentReportsProvider);
    final all = reportsAsync.valueOrNull ?? const <CommentReport>[];
    final unresolved = all.where((r) => !r.resolved).toList();
    final resolved = all.where((r) => r.resolved).toList();

    return AppScrollTabScaffold(
      length: 2,
      title: Text(context.t.adminCommentReports),
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
                resolved.map((r) =>
                    ref.read(adminServiceProvider).deleteCommentReport(r.id)),
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
      tabs: [
        Tab(text: context.t.adminTabOpen(unresolved.length)),
        Tab(text: context.t.adminTabResolved(resolved.length)),
      ],
      body: reportsAsync.when(
        loading: () => const SkeletonList(count: 6),
        error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
        data: (_) => TabBarView(
          children: [
            _CommentReportsList(
              reports: unresolved,
              emptyTitle: context.t.adminNoCommentReports,
              emptySubtitle: context.t.adminFreshReportsHere,
            ),
            _CommentReportsList(
              reports: resolved,
              emptyTitle: context.t.adminNothingResolvedYet,
              emptySubtitle: context.t.adminClosedReportsMoveHere,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentReportsList extends StatelessWidget {
  final List<CommentReport> reports;
  final String emptyTitle;
  final String emptySubtitle;

  const _CommentReportsList({
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
              Icon(Icons.mode_comment_outlined,
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: reports.length,
      itemBuilder: (_, i) => _CommentReportTile(report: reports[i]),
    );
  }
}

class _CommentReportTile extends ConsumerWidget {
  final CommentReport report;

  const _CommentReportTile({required this.report});

  String _shortTime(DateTime? dt) =>
      dt == null ? 'unknown time' : DateFormat('MMM d, HH:mm').format(dt);

  String _fullTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    return DateFormat('EEE, MMM d, yyyy · HH:mm:ss').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = report.commentText.trim().isEmpty
        ? context.t.adminNoCaption
        : report.commentText.trim();

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      borderAlpha: report.resolved ? null : 0.65,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            report.resolved
                ? Icons.check_circle_outline
                : Icons.mode_comment_outlined,
            color: report.resolved ? Colors.green : const Color(0xFFE04E5C),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.t.copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: 'When: ${_fullTime(report.createdAt)}\n'
                        'Reason: ${report.reason}\n'
                        'Surface: ${report.surface}\n'
                        'Reporter: ${report.reporterUsername} (${report.reporterUid})\n'
                        'Comment author: ${report.commentAuthorUsername} (${report.commentAuthorUid})\n'
                        'Post id: ${report.postId}\n'
                        'Comment id: ${report.commentId}\n\n'
                        'Comment: $text\n\n'
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
            text,
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
                _pill(context, Icons.layers_outlined, report.surface),
                _pill(context, Icons.schedule, _shortTime(report.createdAt)),
              ],
            ),
          ),
          children: [
            _kv(context, context.t.adminReportedComment, text),
            _kv(
              context,
              context.t.adminCommentAuthor,
              report.commentAuthorUsername.isEmpty
                  ? report.commentAuthorUid
                  : '${report.commentAuthorUsername} (${report.commentAuthorUid})',
            ),
            _kv(
              context,
              context.t.adminReporter,
              report.reporterUsername.isEmpty
                  ? report.reporterUid
                  : '${report.reporterUsername} (${report.reporterUid})',
            ),
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
                      .setCommentReportResolved(report.id, !report.resolved),
                  child: Text(report.resolved
                      ? context.t.adminReopen
                      : context.t.adminMarkResolved),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: report.postId),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.t.adminViewPost),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () => _onPrimaryAction(context, ref),
                  child: Text(
                    report.resolved
                        ? context.t.adminDeleteReport
                        : context.t.adminTakeDownComment,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPrimaryAction(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(report.resolved
            ? ctx.t.adminDeleteReportTitle
            : ctx.t.adminTakeDownCommentTitle),
        content: Text(report.resolved
            ? ctx.t.adminDeleteReportBody
            : ctx.t.adminTakeDownCommentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(report.resolved
                ? ctx.t.adminDeleteReport
                : ctx.t.adminTakeDownComment),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final admin = ref.read(adminServiceProvider);
    try {
      if (report.resolved) {
        await admin.deleteCommentReport(report.id);
        if (!context.mounted) return;
        AppFeedback.showSuccess(context, context.t.adminReportDeleted);
        return;
      }
      // Take down: delete the comment via the comment service, then
      // mark the report resolved.
      await ref.read(commentServiceProvider).deleteCommentAsAdmin(
            postId: report.postId,
            commentId: report.commentId,
          );
      await admin.setCommentReportResolved(report.id, true);
      if (!context.mounted) return;
      AppFeedback.showSuccess(context, context.t.adminCommentTakenDown);
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.showError(context, context.t.adminActionFailed(e));
    }
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
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              v,
              style: TextStyle(fontSize: 13, color: context.textPrimary),
            ),
          ],
        ),
      );
}
