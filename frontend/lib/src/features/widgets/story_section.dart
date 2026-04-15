import 'package:flutter/material.dart';
import 'story_item.dart';

class StoriesList extends StatelessWidget {
  const StoriesList({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.only(left: 5),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _myStory(),
          ...List.generate(6, (index) => const StoryItem()),
        ],
      ),
    );
  }

  Widget _myStory() {
    return const Padding(
      padding: EdgeInsets.only(right: 10),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage("https://i.pravatar.cc/150"),
              ),
              
            ],
          ),
          SizedBox(height: 4),
          Text("Your Story", style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}