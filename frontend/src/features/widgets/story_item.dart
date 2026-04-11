import 'package:flutter/material.dart';

class StoryItem extends StatelessWidget {
  const StoryItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Color(0xFF9B2282),
                  Color(0xFFEEA863),
                ],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const CircleAvatar(
                radius: 26,
                backgroundImage: NetworkImage("https://i.pravatar.cc/150"),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "User",
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}