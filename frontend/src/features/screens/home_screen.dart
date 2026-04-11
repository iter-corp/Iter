import 'package:flutter/material.dart';
import '../model/post_model.dart';
import '../widgets/header.dart';
import '../widgets/post_card.dart';
import '../widgets/story_section.dart';

final List<Post> posts = [
  Post(
    image: "assets/img/1.png",
    username: "Hike_With_Me",
    handle: "@jack09",
    caption: "What a beautiful nature #hike #mountain #life",
    avatar: "https://i.pravatar.cc/150?img=1",
    isPrivate: false,
  ),
  Post(
    image: "assets/img/2.png",
    username: "Arianaa",
    handle: "@ariana26",
    caption: "Exploring mountains 🏔️",
    avatar: "https://i.pravatar.cc/150?img=2",
    isPrivate: true,
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFE8EAF0),
      body: HomeBody(),
    );
  }
}

class HomeBody extends StatelessWidget {
  const HomeBody({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const HeaderWidget(),
          const StoriesList(),
          Expanded(
            child: ListView.builder(
              itemCount: posts.length,
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemBuilder: (context, index) {
                return PostCard(post: posts[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}