import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/post_providers.dart';
import '../model/post_model.dart';
import '../screens/user_screen.dart';
import '../screens/comment_screen.dart';

class PostCard extends ConsumerWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLikedAsync = ref.watch(isLikedProvider(post.id));
    final isLiked = isLikedAsync.value ?? false;
    final hasImage = post.imageUrls.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: hasImage
                ? CachedNetworkImage(
                    imageUrl: post.imageUrls.first,
                    height: 400,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 400,
                    width: double.infinity,
                    color: const Color(0xFF2B2D30),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      post.caption,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          if (hasImage)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(uid: post.authorUid),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey.shade700,
                      backgroundImage: post.authorAvatar != null
                          ? CachedNetworkImageProvider(post.authorAvatar!)
                          : null,
                      child: post.authorAvatar == null
                          ? const Icon(Icons.person,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorUsername,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () =>
                          ref.read(postServiceProvider).toggleLike(post.id),
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? Colors.red : Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text('${post.likesCount}',
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => CommentScreen(post: post),
                      ),
                      child: _miniIcon(
                          'assets/icons/Group.svg', '${post.commentsCount}'),
                    ),
                    const SizedBox(width: 16),
                    _miniIcon('assets/icons/Send.svg', ''),
                    const Spacer(),
                    _miniIcon('assets/icons/Bookmark.svg', ''),
                  ],
                ),
                if (hasImage) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.caption,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIcon(String svgPath, String text) {
    return Row(
      children: [
        SvgPicture.asset(
          svgPath,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const SizedBox(width: 20, height: 20),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}
