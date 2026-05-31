import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../utils/media_cache.dart';
import '../../providers/post_providers.dart';
import '../../services/post_service.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';
import 'camera_story_screen.dart';
import 'create_post_screen.dart';
import 'qa_thread_screen.dart';

class CreateDiscussScreen extends ConsumerStatefulWidget {
  /// When set, this screen starts a discussion *about* an existing post:
  /// the kind toggle and bottom tab switcher are hidden, a compact preview
  /// of the source post is shown, and submitting links the new thread back
  /// to it via [PostService.createQaPostFromPost], then opens the thread.
  final Post? sourcePost;

  const CreateDiscussScreen({super.key, this.sourcePost});

  @override
  ConsumerState<CreateDiscussScreen> createState() =>
      _CreateDiscussScreenState();
}

class _CreateDiscussScreenState extends ConsumerState<CreateDiscussScreen> {
  final _questionCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _kind = 'question';
  bool _submitting = false;

  bool get _aboutPost => widget.sourcePost != null;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // When discussing an existing post the kind is always "discussion"; the
    // toggle is hidden so the source-post context can't be turned into an
    // unrelated standalone question.
    final isDiscussion = _aboutPost || _kind == 'discussion';

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
                    // Compact preview of the post being discussed.
                    if (_aboutPost) ...[
                      _SourcePostPreview(post: widget.sourcePost!),
                      const SizedBox(height: 16),
                    ],
                    // Kind toggle — sliding-pill style matching MessageTabBar.
                    // Hidden when discussing an existing post (always a
                    // discussion in that case).
                    if (!_aboutPost)
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
                    if (!_aboutPost) const SizedBox(height: 16),
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

              // Bottom pill tab switcher — inside body, same as
              // CreatePostScreen. Hidden when discussing an existing post:
              // switching to Post/Story creation has no meaning there.
              if (!_aboutPost)
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
    final navigator = Navigator.of(context);
    final blockedTitle = t.homeQuestionBlockedTitle;
    final blockedBody = t.homeQuestionBlockedBody;
    final postService = ref.read(postServiceProvider);
    try {
      if (_aboutPost) {
        // Discussion about an existing post: link it back to the source and
        // open the new thread (replacing this screen in the stack).
        final topicId = await postService.createQaPostFromPost(
          widget.sourcePost!,
          question: question,
          details: _detailsCtrl.text.trim(),
        );
        final qaPost = await postService.getPostById(topicId);
        if (!mounted) return;
        if (qaPost != null) {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => QaThreadScreen(post: qaPost)),
          );
        } else {
          navigator.pop();
        }
        return;
      }
      await postService.createQaPost(
        question: question,
        details: _detailsCtrl.text.trim(),
        discussKind: _kind,
      );
      if (mounted) navigator.pop();
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

/// Compact, non-tappable preview of the post a discussion is being started
/// about — shown atop [CreateDiscussScreen] when `sourcePost` is set so the
/// user has context for the question they're writing. Mirrors the embedded
/// card in the QA thread, minus the tap-to-open behaviour.
class _SourcePostPreview extends StatelessWidget {
  final Post post;

  const _SourcePostPreview({required this.post});

  @override
  Widget build(BuildContext context) {
    final hasImage = post.imageUrls.isNotEmpty;
    final cap = post.caption.trim();
    final avatar = post.authorAvatar;

    return AppGlassCard(
      radius: 14,
      surfaceAlpha: context.isDark ? 0.20 : 0.46,
      borderAlpha: context.isDark ? 0.12 : 0.42,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: context.purpleSoft,
                  backgroundImage: (avatar != null && avatar.isNotEmpty)
                      ? NetworkImage(avatar)
                      : null,
                  child: (avatar == null || avatar.isEmpty)
                      ? Icon(Icons.person, size: 13, color: context.textSecondary)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.authorUsername,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: CachedNetworkImage(
                  imageUrl: post.imageUrls.first,
                  cacheManager: MediaCache.images,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: context.borderColor),
                ),
              ),
            ),
          if (cap.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                cap,
                maxLines: hasImage ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: context.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
