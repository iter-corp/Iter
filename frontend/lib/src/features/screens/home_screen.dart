import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_providers.dart';
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
    // Tolerate the adminConfig doc being missing or the rules not yet
    // deployed — both should fail silently (no banner shown).
    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final announcement = cfg?.announcement ?? '';
    final maintenance = cfg?.maintenanceMode ?? false;

    return SafeArea(
      child: Column(
        children: [
          const HeaderWidget(),
          if (announcement.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFD044E8).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined,
                      color: Color(0xFFD044E8), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      announcement,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (maintenance)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Maintenance mode — some features may be unavailable.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
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
