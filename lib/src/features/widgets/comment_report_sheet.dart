import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/comment_providers.dart';
import '../../services/comment_service.dart';
import '../../theme/app_theme.dart';

const List<String> _kCommentReportReasons = [
  'Spam or scam',
  'Harassment or bullying',
  'Hate speech',
  'Violence or threats',
  'Nudity or sexual content',
  'Misinformation',
  'Something else',
];

/// Shared "report this comment" flow used by comments, replies, discuss
/// answers and answer replies. Asks for confirmation first, then shows
/// the standard reason-picker modal and files the report via
/// [CommentService.reportComment]. [surface] is 'comment' | 'answer' |
/// 'reply' and is recorded on the report for admin context.
Future<void> reportCommentFlow(
  BuildContext context,
  WidgetRef ref, {
  required String postId,
  required Comment comment,
  String surface = 'comment',
}) async {
  // Step 1 — confirm intent.
  final wantsReport = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.t.commentReport),
      content: Text(ctx.t.commentReportPickReason),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.t.continueLabel),
        ),
      ],
    ),
  );
  if (wantsReport != true || !context.mounted) return;

  // Step 2 — reason picker modal.
  final detailsCtrl = TextEditingController();
  var selectedReason = _kCommentReportReasons.first;

  try {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.t.commentReport,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        context.t.commentReportPickReason,
                        style: TextStyle(color: context.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ..._kCommentReportReasons.map(
                        (reason) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: reason,
                          groupValue: selectedReason,
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => selectedReason = value);
                          },
                          title: Text(
                            context.t.reportReasonLabel(reason),
                            style: TextStyle(color: context.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: detailsCtrl,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: context.t.homeExtraDetailsOptional,
                          filled: true,
                          fillColor: context.inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: context.borderColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(sheetContext, false),
                              child: Text(context.t.cancel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.pop(sheetContext, true),
                              child: Text(context.t.homeSendReport),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (submitted != true) return;

    await ref.read(commentServiceProvider).reportComment(
          postId: postId,
          comment: comment,
          reason: selectedReason,
          details: detailsCtrl.text.trim(),
          surface: surface,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.commentReportSent)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.commentReportFailed(e.toString()))),
    );
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) => detailsCtrl.dispose());
  }
}
