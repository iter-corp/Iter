import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../model/post_model.dart';
import '../screens/user_screen.dart';

class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Stack(
        children: [
          /// IMAGE
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              widget.post.image,
              height: 400,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),

          /// GRADIENT
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

          /// USER INFO
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      username: widget.post.username,
                      handle: widget.post.handle,
                      avatar: widget.post.avatar,
                      isPrivate: widget.post.isPrivate,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage:
                          NetworkImage(widget.post.avatar),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          widget.post.handle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// MORE ICON
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF404145),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  builder: (context) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildBottomSheetItem(
                            "assets/icons/Bookmark.svg",
                            "Save",
                            Colors.white),
                        _buildBottomSheetItem(
                            "assets/icons/user-unfollow.svg",
                            "Unfollow",
                            Colors.white),
                        _buildBottomSheetItem(
                            "assets/icons/Hide.svg",
                            "Hide",
                            Colors.white),
                        _buildBottomSheetItem(
                            "assets/icons/Material.svg",
                            "About this account",
                            Colors.white),
                        _buildBottomSheetItem(
                            "assets/icons/Report.svg",
                            "Report",
                            Colors.red),
                      ],
                    );
                  },
                );
              },
              child: Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.more_vert,
                    color: Colors.white, size: 20),
              ),
            ),
          ),

          /// BOTTOM CONTENT
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
                    _buildInteractiveIcon(
                        "assets/icons/Vector.svg", "1804"),
                    const SizedBox(width: 12),
                    _buildInteractiveIcon(
                        "assets/icons/Group.svg", "152"),
                    const SizedBox(width: 12),
                    _buildInteractiveIcon(
                        "assets/icons/Send.svg", "16"),
                    const SizedBox(width: 12),
                    _buildInteractiveIcon(
                        "assets/icons/Repost.svg", "4"),
                    const Spacer(),
                    _buildInteractiveIcon(
                        "assets/icons/Bookmark.svg", ""),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.post.caption,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheetItem(
      String svgPath, String title, Color iconColor) {
    return ListTile(
      leading: SvgPicture.asset(
        svgPath,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        placeholderBuilder: (context) => const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 1),
        ),
      ),
      title: Text(title,
          style: TextStyle(
              color: iconColor == Colors.red
                  ? Colors.red
                  : Colors.white)),
      onTap: () => Navigator.pop(context),
    );
  }

  Widget _buildInteractiveIcon(String svgPath, String text) {
    return Row(
      children: [
        SvgPicture.asset(
          svgPath,
          width: 20,
          height: 20,
          colorFilter:
              const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (context) => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 1),
          ),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ],
      );
  }
}
