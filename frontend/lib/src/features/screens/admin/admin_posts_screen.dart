import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';

class AdminPostsScreen extends ConsumerWidget {
  const AdminPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(adminPostsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Posts'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(
                child: Text('No posts', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: posts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = posts[i];
              final imgs = (p['imageUrls'] as List?)?.cast<String>() ?? const [];
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
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.text_fields,
                                color: Colors.grey),
                          ),
                  ),
                ),
                title: Text(
                  (p['caption'] as String? ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'by ${p['authorUsername'] ?? 'unknown'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
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
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(adminServiceProvider).deletePost(postId);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }
}
