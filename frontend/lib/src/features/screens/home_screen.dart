import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/post_providers.dart';
import '../widgets/header.dart';
import '../widgets/post_card.dart';
import '../widgets/story_section.dart';

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

class HomeBody extends ConsumerWidget {
  const HomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);

    return SafeArea(
      child: Column(
        children: [
          const HeaderWidget(),
          const StoriesList(),
          Expanded(
            child: feedAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (posts) {
                if (posts.isEmpty) {
                  return const Center(
                    child: Text('No posts yet. Create the first one!'),
                  );
                }
                return ListView.builder(
                  itemCount: posts.length,
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  itemBuilder: (context, index) =>
                      PostCard(post: posts[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
