import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';
import '../../widgets/skeleton_loader.dart';
import '../post_detail_screen.dart';

class AdminPostsScreen extends ConsumerStatefulWidget {
  const AdminPostsScreen({super.key});

  @override
  ConsumerState<AdminPostsScreen> createState() => _AdminPostsScreenState();
}

class _AdminPostsScreenState extends ConsumerState<AdminPostsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(adminPostsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.adminTilePostsTitle),
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: true,
              snap: true,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AppGlassCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: false,
                        fillColor: Colors.transparent,
                      ),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        hintText: context.t.adminSearchByUsernameOrCaption,
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            postsAsync.when<Widget>(
              loading: () => SkeletonListTile.sliver(count: 6),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(context.t.errorWithMessage(e))),
              ),
              data: (allPosts) {
                final q = _query.trim().toLowerCase();
                final posts = q.isEmpty
                    ? allPosts
                    : allPosts.where((p) {
                        final author = (p['authorUsername'] as String? ?? '')
                            .toLowerCase();
                        final caption =
                            (p['caption'] as String? ?? '').toLowerCase();
                        return author.contains(q) || caption.contains(q);
                      }).toList();
                if (posts.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                          q.isEmpty
                              ? context.t.noPosts
                              : context.t.adminNoPostsMatch,
                          style: TextStyle(color: context.textSecondary)),
                    ),
                  );
                }
                final bottomPadding =
                    MediaQuery.viewPaddingOf(context).bottom + 28;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
                  sliver: SliverList.builder(
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final p = posts[i];
                      final imgs =
                          (p['imageUrls'] as List?)?.cast<String>() ?? const [];
                      final url = imgs.isNotEmpty ? imgs.first : null;
                      final caption = (p['caption'] as String? ?? '').trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppGlassCard(
                          radius: 16,
                          child: ListTile(
                            onTap: () {
                              final postId = (p['id'] as String? ?? '').trim();
                              if (postId.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PostDetailScreen(postId: postId),
                                ),
                              );
                            },
                            leading: SizedBox(
                              width: 52,
                              height: 52,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: url != null
                                    ? CachedNetworkImage(
                                        imageUrl: url, fit: BoxFit.cover)
                                    : Container(
                                        color: context.inputFill,
                                        child: Icon(Icons.text_fields,
                                            color: context.textSecondary),
                                      ),
                              ),
                            ),
                            title: Text(
                              caption.isEmpty
                                  ? context.t.adminNoCaption
                                  : caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              context.t.adminPostByAuthor(p['authorUsername'] ??
                                  context.t.adminUnknown),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.textSecondary, fontSize: 12),
                            ),
                            trailing: IconButton(
                              onPressed: () =>
                                  _delete(context, ref, p['id'] as String),
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.postCardDeletePostTitle),
        content: Text(context.t.postCardCannotBeUndone),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.delete,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(adminServiceProvider).deletePost(postId);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.failedWithError(e))));
        }
      }
    }
  }
}
