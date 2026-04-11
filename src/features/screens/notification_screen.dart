import 'package:flutter/material.dart';

import '../widgets/notification_tile.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                  onPressed: (){
                    Navigator.pop(context);
                  },
                   icon: const Icon(Icons.arrow_back, size: 26),
                   ),
                  const SizedBox(width: 12),
                  const Text(
                    "Notifications",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            /// LIST
            Expanded(
              child: ListView(
                children: const [
                  /// FOLLOW BACK
                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=1",
                    title: "Hike_With_Me",
                    subtitle: "3 friend",
                    trailingType: NotificationType.followBack,
                  ),

                  /// COMMENT
                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=2",
                    title: "hike_With_Me commented on your post",
                    subtitle: "very nice weather  3 h",
                    postImage: "assets/img/1.png",
                    trailingType: NotificationType.image,
                  ),

                  /// LIKE
                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=3",
                    title: "Sara_Ali liked your post",
                    subtitle: "4 h",
                    isLike: true,
                    postImage: "assets/img/1.png",
                    trailingType: NotificationType.image,
                  ),

                  /// LIKE REPOST
                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=4",
                    title: "Anna liked Michael post that you reposted",
                    subtitle: "2 d",
                    isLike: true,
                    postImage: "assets/img/2.png",
                    trailingType: NotificationType.image,
                  ),

                  SizedBox(height: 16),

                  /// SUGGESTED
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "Suggested for you",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),

                  SizedBox(height: 8),

                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=5",
                    title: "Youth Mountaineering Group",
                    subtitle: "1 friend",
                    trailingType: NotificationType.follow,
                  ),

                  NotificationTile(
                    avatar: "https://i.pravatar.cc/150?img=6",
                    title: "Michael",
                    subtitle: "2 friend",
                    trailingType: NotificationType.follow,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}