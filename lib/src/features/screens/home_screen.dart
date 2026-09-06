import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/admin_providers.dart';
import '../../providers/notification_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/post_providers.dart';
import '../../services/translate_service.dart';
import '../../utils/media_cache.dart';
import '../model/post_model.dart';
import 'create_post_screen.dart';
import 'notification_screen.dart';
import 'post_detail_screen.dart';
import 'qa_thread_screen.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/post_card.dart';
import '../widgets/story_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Transparent so the per-tab background painted by MainScreen
    // shows through — otherwise a white Scaffold here peeked out as
    // strips above/below the SafeArea content.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: HomeBody(),
    );
  }
}

class HomeBody extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const HomeBody({super.key, this.scrollController});

  @override
  ConsumerState<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<HomeBody> {
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(feedProvider);
    ref.invalidate(qaFeedProvider);
    ref.invalidate(nasaFeedProvider);
    ref.invalidate(wikimediaFeedProvider);
    try {
      await ref.read(feedProvider.future);
    } catch (_) {
      // Swallow — the error state already renders in the list.
    }
    try {
      await ref.read(qaFeedProvider.future);
    } catch (_) {
      // Swallow — the error state already renders in the list.
    }
    try {
      await ref.read(nasaFeedProvider.future);
    } catch (_) {
      // Swallow — the error state already renders in the list.
    }
    try {
      await ref.read(wikimediaFeedProvider.future);
    } catch (_) {
      // Swallow — the error state already renders in the list.
    }
  }

  /// Top content for the scrolling list: banners, the app bar, and stories.
  List<Widget> _topContent({
    required String announcement,
    required bool maintenance,
    required bool showStories,
  }) {
    return [
      if (announcement.isNotEmpty)
        _AnnouncementBanner(announcement: announcement),
      if (maintenance) const _MaintenanceBanner(),
      const SizedBox(height: 8),
      // App-bar row — "Itr" title + Post button + notification bell.
      _HomeTopBar(
        onPost: () => _openCreatePost(context),
      ),
      // Stories — directly under the tabs, identical on every tab.
      if (showStories) const StoriesList(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(homeFeedProvider);

    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final announcement = cfg?.announcement ?? '';
    final maintenance = cfg?.maintenanceMode ?? false;
    final showStories = cfg?.storiesEnabled ?? true;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: postsAsync.when(
          loading: () => ListView(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              ..._topContent(
                announcement: announcement,
                maintenance: maintenance,
                showStories: showStories,
              ),
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (e, _) => ListView(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              ..._topContent(
                announcement: announcement,
                maintenance: maintenance,
                showStories: showStories,
              ),
              const SizedBox(height: 24),
              Center(child: Text(context.t.homeErrorPrefix(e))),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  ..._topContent(
                    announcement: announcement,
                    maintenance: maintenance,
                    showStories: showStories,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(context.t.homeNoPostsCreateFirst),
                  ),
                ],
              );
            }

            return CustomScrollView(
              controller: widget.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: _topContent(
                      announcement: announcement,
                      maintenance: maintenance,
                      showStories: showStories,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      if (item.isQa) {
                        return QaThreadCard(
                            key: ValueKey(item.post.id), post: item.post);
                      }
                      return PostCard(
                        key: ValueKey(item.post.id),
                        post: item.post,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreatePost(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    ref.invalidate(feedProvider);
  }
}

/// Home app-bar: the "Itr" brand title centred, Post button on the
/// leading side, and the notification bell trailing.
class _HomeTopBar extends ConsumerWidget {
  final VoidCallback onPost;

  const _HomeTopBar({
    required this.onPost,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // Centred: "Itr" title (mode dropdown moved to the search row)
            Align(
              alignment: Alignment.center,
              child: Text(
                context.t.headerAppTitle,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: context.textPrimary,
                ),
              ),
            ),
            // Leading: add-post button (opposite the notification bell).
            // Keeps the original gradient "Post" pill style.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PrimaryActionButton(
                label: context.t.post,
                icon: Icons.add,
                onPressed: onPost,
              ),
            ),
            // Trailing: notification bell (start side in RTL).
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _NotificationBell(unreadCount: unreadCount),
            ),
          ],
        ),
      ),
    );
  }
}

/// The notification bell with an unread-count badge.
class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  const _NotificationBell({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_outlined,
              size: 26, color: context.textPrimary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationScreen()),
          ),
        ),
        if (unreadCount > 0)
          PositionedDirectional(
            end: 6,
            top: 6,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: AppColors.purple,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class QaThreadCard extends ConsumerWidget {
  final Post post;

  const QaThreadCard({super.key, required this.post});

  static const List<String> _reportReasons = [
    'Spam or scam',
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Nudity or sexual content',
    'Misinformation',
    'Something else',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final isLiked = ref.watch(isLikedProvider(post.id)).value ?? false;
    final canDelete = currentUid != null && currentUid == post.authorUid;
    final canReport = currentUid != null && currentUid != post.authorUid;
    final caption = post.caption.trim();
    final lines = caption
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title = lines.isEmpty ? context.t.qaUntitledQuestion : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    final preview = _twoSentencePreview(body);
    final timeLabel = context.t.timeAgo(post.createdAt);
    final isQuestion = post.discussKind == 'question' ||
        (post.discussKind == null && title.contains('?'));

    void openThread() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QaThreadScreen(post: post),
        ),
      );
    }

    Future<void> translatePost() async {
      if (caption.isEmpty) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _DiscussTranslateSheet(
          text: caption,
          target: ref.read(preferredLanguageProvider),
        ),
      );
    }

    return AppGlassCard(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      radius: 18,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: openThread,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.purpleSoft,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        isQuestion
                            ? Icons.help_outline_rounded
                            : Icons.forum_outlined,
                        size: 18,
                        color: const Color(0xFF7E3BE8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.purpleSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isQuestion
                            ? context.t.homeQuestionLabel
                            : context.t.homeDiscussionLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7E3BE8),
                        ),
                      ),
                    ),
                    if (canDelete || canReport) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: context.t.homeQuestionActions,
                        icon: Icon(Icons.more_horiz,
                            color: context.textSecondary),
                        onSelected: (value) async {
                          if (value == 'report') {
                            await _reportQuestion(context, ref);
                            return;
                          }
                          if (value != 'delete') return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(context.t.homeDeleteQuestionTitle),
                              content: Text(context.t.homeDeleteQuestionBody),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: Text(context.t.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: Text(context.t.delete),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;
                          try {
                            await ref
                                .read(postServiceProvider)
                                .deletePost(post.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(context.t.homeQuestionDeleted)),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text(context.t.homeCouldNotDelete(e))),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          if (canReport)
                            PopupMenuItem<String>(
                              value: 'report',
                              child: Row(children: [
                                const Icon(
                                  Icons.flag_outlined,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.t.homeReportQuestionMenu,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ]),
                            ),
                          if (canDelete)
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(context.t.homeDeleteQuestionMenu),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                // When this discuss item was created from a post, show
                // a mini preview of that post.
                if (post.sourcePostId != null &&
                    post.sourcePostId!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MiniPostPreview(postId: post.sourcePostId!),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QaMeta(
                      icon: Icons.forum_outlined,
                      label: context.t.homeDiscuss,
                      onTap: openThread,
                    ),
                    if (caption.isNotEmpty)
                      _QaMeta(
                        icon: Icons.translate,
                        label: context.t.translate,
                        onTap: translatePost,
                      ),
                    _QaMeta(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      label: '',
                      highlighted: isLiked,
                      onTap: () async {
                        try {
                          await ref
                              .read(postServiceProvider)
                              .toggleLike(post.id);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(context.t.homeErrorPrefix(e))),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reportQuestion(BuildContext context, WidgetRef ref) async {
    final detailsCtrl = TextEditingController();
    var selectedReason = _reportReasons.first;

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
                                context.t.homeReportQuestionMenu,
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
                          context.t.homePickReasonQuestion,
                          style: TextStyle(color: context.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        ..._reportReasons.map(
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

      await ref.read(postServiceProvider).reportQaPost(
            post: post,
            reason: selectedReason,
            details: detailsCtrl.text,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeReportSentAdmins)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeCouldNotReportQuestion(e))),
      );
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => detailsCtrl.dispose());
    }
  }
}

class _MiniPostPreview extends ConsumerWidget {
  final String postId;

  const _MiniPostPreview({required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(singlePostProvider(postId));

    return postAsync.when(
      loading: () => Container(
        height: 60,
        decoration: BoxDecoration(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (src) {
        if (src == null) return const SizedBox.shrink();
        final hasImage = src.imageUrls.isNotEmpty;
        final cap = src.caption.trim();

        return Material(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(postId: src.id),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              // IntrinsicHeight gives the Row a definite height (the
              // text column's natural height) so the stretched
              // thumbnail has a bounded height — without it, stretch
              // forces infinite height and the layout crashes.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Thumbnail (if the post has an image).
                    if (hasImage)
                      SizedBox(
                        width: 70,
                        child: CachedNetworkImage(
                          imageUrl: src.imageUrls.first,
                          cacheManager: MediaCache.images,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: context.borderColor),
                        ),
                      ),
                    // Author + caption.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 9,
                                  backgroundColor: context.purpleSoft,
                                  backgroundImage: (src.authorAvatar != null &&
                                          src.authorAvatar!.isNotEmpty)
                                      ? CachedNetworkImageProvider(
                                          src.authorAvatar!)
                                      : null,
                                  child: (src.authorAvatar == null ||
                                          src.authorAvatar!.isEmpty)
                                      ? Icon(Icons.person,
                                          size: 11,
                                          color: context.textSecondary)
                                      : null,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    src.authorUsername,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 16, color: context.textMuted),
                              ],
                            ),
                            if (cap.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                cap,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _twoSentencePreview(String text) {
  final normalized = text.replaceAll('\n', ' ').trim();
  if (normalized.isEmpty) return '';
  final parts = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(normalized)
      .map((m) => (m.group(0) ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return normalized;
  return parts.take(2).join(' ');
}

class _QaMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final VoidCallback? onTap;

  const _QaMeta({
    required this.icon,
    required this.label,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? const Color(0xFF7E3BE8) : context.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted ? context.purpleSoft : context.inputFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscussTranslateSheet extends StatefulWidget {
  final String text;
  final String target;

  const _DiscussTranslateSheet({
    required this.text,
    required this.target,
  });

  @override
  State<_DiscussTranslateSheet> createState() => _DiscussTranslateSheetState();
}

class _DiscussTranslateSheetState extends State<_DiscussTranslateSheet> {
  late String _target;
  String? _translated;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _translate();
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await const TranslateService().translateText(
        text: widget.text,
        sourceLang: 'auto',
        targetLang: _target,
      );
      if (!mounted) return;
      setState(() {
        _translated = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TranslateService.userFriendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _selectLang(String code) {
    if (code == _target) return;
    setState(() => _target = code);
    _translate();
  }

  String _labelOf(String code) => kTranslateLanguages
      .firstWhere((l) => l.code == code,
          orElse: () => const TranslateLanguage('?', '?'))
      .label;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final chipLangs = <TranslateLanguage>[];
    for (final lang in kTranslateLanguages) {
      if (seen.add(lang.code)) chipLangs.add(lang);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.t.commentTranslateTo(_labelOf(_target)),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chipLangs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final lang = chipLangs[i];
                  final selected = lang.code == _target;
                  final label = lang.code == 'en' ? 'English' : lang.label;
                  return GestureDetector(
                    onTap: () => _selectLang(lang.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFB05ECC)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              SelectableText(
                _translated ?? '',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  final String announcement;

  const _AnnouncementBanner({required this.announcement});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:
            context.isDark ? const Color(0xFF2D1A30) : const Color(0xFFFFF1F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD044E8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: Color(0xFFD044E8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              announcement,
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceBanner extends StatelessWidget {
  const _MaintenanceBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF3D2E1A) : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t.homeMaintenanceMode,
              style: TextStyle(fontSize: 13, color: context.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
