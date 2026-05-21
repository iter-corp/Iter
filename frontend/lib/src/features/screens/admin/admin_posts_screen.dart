import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';

class AdminPostsScreen extends ConsumerWidget {
  const AdminPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(adminPostsProvider);
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(context.t.adminTilePostsTitle),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
        data: (posts) {
          if (posts.isEmpty) {
            return Center(
                child: Text(context.t.noPosts,
                    style: TextStyle(color: context.textSecondary)));
          }
          return ListView.separated(
            itemCount: posts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = posts[i];
              final imgs =
                  (p['imageUrls'] as List?)?.cast<String>() ?? const [];
              final url = imgs.isNotEmpty ? imgs.first : null;
              return ListTile(
                leading: SizedBox(
                  width: 52,
                  height: 52,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: url != null
                        ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                        : Container(
                            color: context.inputFill,
                            child: Icon(Icons.text_fields,
                                color: context.textSecondary),
                          ),
                  ),
                ),
                title: Text(
                  (p['caption'] as String? ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.t.adminPostByAuthor(
                      p['authorUsername'] ?? context.t.adminUnknown),
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: IconButton(
                  onPressed: () => _delete(context, ref, p['id'] as String),
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              );
            },
          );
        },
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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
        }
      }
    }
  }
}
