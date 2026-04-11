import 'package:flutter/material.dart';

import '../screens/create_post_screen.dart';
import '../screens/notification_screen.dart';

class HeaderWidget extends StatelessWidget {
  const HeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreatePostScreen(),
                ),
              );
            },
          ),

          const Expanded(
            child: Center(
              child: Text(
                "Coil",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        IconButton(
        icon: const Icon(Icons.notifications_outlined, size: 26),
        onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationScreen(),
                ),
              );
            },
      ),
        ],
      ),
    );
  }
}