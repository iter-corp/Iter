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
  final ScrollController? scrollController;

  const HomeBody({super.key, this.scrollController});

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
          Expanded(
            child: feedAsync.when(
              loading: () => ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  if (announcement.isNotEmpty)
                    _AnnouncementBanner(announcement: announcement),
                  if (maintenance) const _MaintenanceBanner(),
                  const StoriesList(),
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
              error: (e, _) => ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  if (announcement.isNotEmpty)
                    _AnnouncementBanner(announcement: announcement),
                  if (maintenance) const _MaintenanceBanner(),
                  const StoriesList(),
                  const SizedBox(height: 24),
                  Center(child: Text('Error: $e')),
                ],
              ),
              data: (posts) {
                if (posts.isEmpty) {
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      if (announcement.isNotEmpty)
                        _AnnouncementBanner(announcement: announcement),
                      if (maintenance) const _MaintenanceBanner(),
                      const StoriesList(),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text('No posts yet. Create the first one!'),
                      ),
                    ],
                  );
                }
                return CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    if (announcement.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _AnnouncementBanner(announcement: announcement),
                      ),
                    if (maintenance)
                      const SliverToBoxAdapter(child: _MaintenanceBanner()),
                    const SliverToBoxAdapter(child: StoriesList()),
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 8, bottom: 100),
                      sliver: SliverList.builder(
                        itemCount: posts.length,
                        itemBuilder: (context, index) =>
                            PostCard(post: posts[index]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  final String announcement;

  const _AnnouncementBanner({required this.announcement});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD044E8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: Color(0xFFD044E8),
            size: 18,
          ),
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
    );
  }
}

class _MaintenanceBanner extends StatelessWidget {
  const _MaintenanceBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Maintenance mode — some features may be unavailable.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
