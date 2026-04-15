import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_providers.dart';
import '../../services/admin_service.dart';
import '../widgets/event_detail.dart';

// 📌 SECTION: Event data model
class EventItem {
  final String imageUrl;
  final String title;
  final String subtitle;
  final String location;
  final String description;
  final String phone;
  final String email;

  // 🔹 Extra images for carousel on detail screen
  final List<String> extraImages;

  const EventItem({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.description,
    required this.phone,
    required this.email,
    this.extraImages = const [],
  });

  // 🔹 All carousel images = cover + extras
  List<String> get allImages => [imageUrl, ...extraImages];
}

// 📌 SECTION: Mock data
final List<EventItem> kEvents = [
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=600',
    title: 'Harvard University',
    subtitle: '@Psychology Group',
    location: 'Cambridge, MA 02138, USA',
    description:
        'Our activity this time was to attend a psychology summit at Harvard University. '
        'It was an incredible experience meeting students and researchers from around the world.',
    phone: 'Phone number',
    email: 'Email',
    extraImages: [
      'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=600',
      'https://images.unsplash.com/photo-1498243691581-b145c3f54a5a?w=600',
    ],
  ),
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=600',
    title: 'MT. Everest',
    subtitle: '@Youth group',
    location: 'Nepal',
    description:
        'Our activity this time was to climb Mount Everest in Nepal & china, one of the highest '
        'mountains in the world at 8.848m, it was a little difficult but it was a special place.',
    phone: 'Phone number',
    email: 'Email',
    extraImages: [
      'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600',
      'https://images.unsplash.com/photo-1486870591958-9b9d0d1dda99?w=600',
    ],
  ),
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=600',
    title: 'Fine Arts Institute',
    subtitle: '@Creative Arts Club',
    location: 'Roma, Italy',
    description:
        'We explored the Fine Arts Institute in Rome, Italy — a vibrant community of creatives '
        'working across painting, sculpture, and mixed media.',
    phone: 'Phone number',
    email: 'Email',
    extraImages: [
      'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=600',
    ],
  ),
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1542744173-8e7e53415bb0?w=600',
    title: 'MAC entreprise Company',
    subtitle: '@Meeting room',
    location: 'Beirut, Lebanon',
    description:
        'A corporate networking event held at MAC entreprise in Beirut, bringing together '
        'business leaders and entrepreneurs for a day of collaboration.',
    phone: 'Phone number',
    email: 'Email',
    extraImages: [
      'https://images.unsplash.com/photo-1556761175-5973dc0f32e7?w=600',
    ],
  ),
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=600',
    title: 'Community Gathering',
    subtitle: '@Cultural Meet',
    location: 'Istanbul, Turkey',
    description:
        'An annual cultural gathering celebrating diversity and community spirit in the heart of Istanbul.',
    phone: 'Phone number',
    email: 'Email',
  ),
  const EventItem(
    imageUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=600',
    title: 'Tech Summit',
    subtitle: '@Innovation Forum',
    location: 'Dubai, UAE',
    description:
        'A premier technology summit covering AI, blockchain, and the future of innovation, '
        'hosted in the tech hub of Dubai.',
    phone: 'Phone number',
    email: 'Email',
  ),
];

// 📌 SECTION: EventBody — grid screen
class EventBody extends ConsumerStatefulWidget {
  const EventBody({super.key});

  @override
  ConsumerState<EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<EventBody> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(adminEventsProvider);
    final q = _query.trim().toLowerCase();
    final events = (eventsAsync.value ?? const <AdminEvent>[]).where((e) {
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.subtitle.toLowerCase().contains(q) ||
          e.location.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 14),
          child: Column(
            children: [
              _SearchBar(controller: _searchController),
              const SizedBox(height: 14),

              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              'No events matching "$_query"',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final event = events[index];
                          return _EventCard(
                            event: event,
                            onSeeMore: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventDetailScreen(
                                    title: event.title,
                                    subtitle: event.subtitle,
                                    location: event.location,
                                    imageUrls: event.imageUrls,
                                    description: event.description,
                                    phone: event.phone,
                                    email: event.email,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 📌 SECTION: Search Bar
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: Color(0xFFAAAAAA)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search...',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

// 📌 SECTION: Event Card
class _EventCard extends StatelessWidget {
  final AdminEvent event;
  final VoidCallback onSeeMore;

  const _EventCard({required this.event, required this.onSeeMore});

  @override
  Widget build(BuildContext context) {
    final coverUrl = event.imageUrls.isNotEmpty ? event.imageUrls.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🔹 Background image
          if (coverUrl != null)
            CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: const Color(0xFFE0E0E0)),
              errorWidget: (_, __, ___) =>
                  Container(color: const Color(0xFFBDBDBD)),
            )
          else
            Container(color: const Color(0xFFBDBDBD)),

          // 🔹 Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.35, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.78),
                  ],
                ),
              ),
            ),
          ),

          // 🔹 Text + button
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  event.subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70, height: 1.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  event.location,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70, height: 1.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onSeeMore, // ✅ navigates to detail
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCE5DE5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'see more',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}