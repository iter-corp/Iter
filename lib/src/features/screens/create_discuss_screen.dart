import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/post_providers.dart';
import '../../services/post_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';
import 'camera_story_screen.dart';
import 'create_post_screen.dart';

class CreateDiscussScreen extends ConsumerStatefulWidget {
  const CreateDiscussScreen({super.key});

  @override
  ConsumerState<CreateDiscussScreen> createState() =>
      _CreateDiscussScreenState();
}

class _CreateDiscussScreenState extends ConsumerState<CreateDiscussScreen> {
  final _questionCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _kind = 'question';
  bool _submitting = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isDiscussion = _kind == 'discussion';

    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(t.homeDiscussionLabel),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Scrollable form content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  children: [
                    // Kind toggle — sliding-pill style matching MessageTabBar
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const pad = 4.0;
                        final pillWidth = (constraints.maxWidth - pad * 2) / 2;
                        return Container(
                          height: 48,
                          padding: const EdgeInsets.all(pad),
                          decoration: BoxDecoration(
                            color: context.cardBg,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Stack(
                            children: [
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                alignment: isDiscussion
                                    ? AlignmentDirectional.centerEnd
                                    : AlignmentDirectional.centerStart,
                                child: Container(
                                  width: pillWidth,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.purple,
                                        AppColors.purpleVivid
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.purple
                                            .withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _kindTab(
                                      context,
                                      Icons.help_outline,
                                      t.homeQuestionLabel,
                                      !isDiscussion,
                                      () => setState(() => _kind = 'question'),
                                    ),
                                  ),
                                  Expanded(
                                    child: _kindTab(
                                      context,
                                      Icons.forum_outlined,
                                      t.homeDiscussionLabel,
                                      isDiscussion,
                                      () =>
                                          setState(() => _kind = 'discussion'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _questionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: isDiscussion
                            ? t.homeWhatsYourDiscussion
                            : t.homeWhatsYourQuestion,
                        filled: true,
                        fillColor: context.inputFill,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _detailsCtrl,
                      minLines: 3,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: t.homeAddMoreContext,
                        filled: true,
                        fillColor: context.inputFill,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryActionButton(
                      label: isDiscussion
                          ? t.homePostDiscussion
                          : t.homePostQuestion,
                      onPressed: _submitting ? null : _submit,
                      loading: _submitting,
                      size: PrimaryActionSize.large,
                      fullWidth: true,
                    ),
                  ],
                ),
              ),

              // Bottom pill tab switcher — inside body, same as CreatePostScreen
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 8),
                child: Center(
                  child: AppGlassCard(
                    radius: 30,
                    surfaceAlpha: context.isDark ? 0.42 : 0.36,
                    borderAlpha: context.isDark ? 0.14 : 0.50,
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _bottomTab2(context, t.post, 0, false),
                        _bottomTab2(context, t.homeDiscussionLabel, 2, true),
                        _bottomTab2(context, t.story, 1, false),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindTab(BuildContext context, IconData icon, String label,
      bool isActive, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 17,
                color: isActive ? Colors.white : context.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : context.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomTab2(
      BuildContext context, String text, int index, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CameraStoryScreen()),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFFD044E8), Color(0xFF7E3BE8)],
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final question = _questionCtrl.text.trim();
    final t = context.t;
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.homeWriteQuestionFirst)),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final blockedTitle = t.homeQuestionBlockedTitle;
    final blockedBody = t.homeQuestionBlockedBody;
    try {
      await ref.read(postServiceProvider).createQaPost(
            question: question,
            details: _detailsCtrl.text.trim(),
            discussKind: _kind,
          );
      if (mounted) Navigator.of(context).pop();
    } on DiscussPostBlockedException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(blockedTitle),
          content: Text(blockedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(dctx.t.ok),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(t.errorWithMessage(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
