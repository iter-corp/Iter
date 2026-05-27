import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';
import '../../model/post_model.dart';
import '../../widgets/app_page_background.dart';
import '../qa_thread_screen.dart';

class AdminDiscussPostsScreen extends ConsumerStatefulWidget {
  const AdminDiscussPostsScreen({super.key});

  @override
  ConsumerState<AdminDiscussPostsScreen> createState() =>
      _AdminDiscussPostsScreenState();
}

class _AdminDiscussPostsScreenState
    extends ConsumerState<AdminDiscussPostsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(adminDiscussPostsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.adminDiscussPosts),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: Column(
          children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: AppGlassCard(
              radius: 16,
              padding: EdgeInsets.zero,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.t.adminDiscussSearchHint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: postsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text(context.t.errorWithMessage(e))),
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
                  return Center(
                    child: Text(
                      q.isEmpty
                          ? context.t.adminDiscussNoPosts
                          : context.t.adminDiscussNoPostsMatch,
                      style: TextStyle(color: context.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                          onTap: () async {
                            final postId = (p['id'] as String? ?? '').trim();
                            if (postId.isEmpty) return;
                            final snap = await FirebaseFirestore.instance
                                .collection('posts')
                                .doc(postId)
                                .get();
                            if (!context.mounted) return;
                            if (!snap.exists) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    QaThreadScreen(post: Post.fromDoc(snap)),
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
                                      child: Icon(Icons.forum_outlined,
                                          color: context.textSecondary),
                                    ),
                            ),
                          ),
                          title: Text(
                            caption.isEmpty
                                ? context.t.adminDiscussNoQuestionText
                                : caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            context.t.adminDiscussByAuthor(
                                (p['authorUsername'] as String?) ?? '—'),
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
                );
              },
            ),
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
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.adminDiscussDeleteTitle),
        content: Text(ctx.t.adminDiscussDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.t.delete,
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
