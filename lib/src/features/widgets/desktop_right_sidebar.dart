import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/admin_providers.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'event_detail.dart';

class DesktopRightSidebar extends ConsumerStatefulWidget {
  final ValueChanged<int> onTabSelected;

  const DesktopRightSidebar({
    super.key,
    required this.onTabSelected,
  });

  @override
  ConsumerState<DesktopRightSidebar> createState() => _DesktopRightSidebarState();
}

class _DesktopRightSidebarState extends ConsumerState<DesktopRightSidebar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eventsAsync = ref.watch(adminEventsProvider);

    return Container(
      width: 330,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C0F17) : const Color(0xFFF7F8FA),
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search Bar ──
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: context.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 14, color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search Iter...',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: context.textMuted,
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) {
                        widget.onTabSelected(2); // Explore / search tab
                      },
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchController.clear();
                        });
                      },
                      child: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // ── Upcoming Events Widget ──
            _buildUpcomingEventsCard(context, eventsAsync, isDark),

            const SizedBox(height: 20),

            // ── Suggested Topics / Trending ──
            _buildTrendingTopicsCard(context, isDark),

            const SizedBox(height: 24),

            // ── Minimal Desktop Footer ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _buildFooterLink('About', () {}),
                  _buildFooterLink('Privacy', () {}),
                  _buildFooterLink('Terms', () {}),
                  _buildFooterLink('Help', () {}),
                  Text(
                    '© 2026 Iter Global',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textMuted.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsCard(
    BuildContext context,
    AsyncValue<List<AdminEvent>> eventsAsync,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: Color(0xFFCE5DE5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Upcoming Events',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => widget.onTabSelected(1), // Events tab
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCE5DE5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          eventsAsync.when(
            data: (events) {
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No upcoming events scheduled yet.',
                    style: TextStyle(fontSize: 13, color: context.textMuted),
                  ),
                );
              }
              final displayEvents = events.take(3).toList();
              return Column(
                children: displayEvents.map((e) => _buildEventItem(context, e, isDark)).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Text(
              'Explore public events and gatherings.',
              style: TextStyle(fontSize: 13, color: context.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(BuildContext context, AdminEvent event, bool isDark) {
    final dateFormat = DateFormat('MMM d');
    final dateStr = event.deadlineAt != null ? dateFormat.format(event.deadlineAt!) : null;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(
              eventId: event.id,
              title: event.title,
              subtitle: event.subtitle,
              location: event.location,
              eventType: event.eventType,
              funds: event.funds,
              deadlineAt: event.deadlineAt,
              imageUrls: event.imageUrls,
              description: event.description,
              link: event.link,
              phone: event.phone,
              email: event.email,
              createdByUid: event.createdByUid,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF7A3FB8).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(
                  Icons.event_available_rounded,
                  size: 20,
                  color: Color(0xFFCE5DE5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (dateStr != null) dateStr,
                      if (event.location.isNotEmpty) event.location.split(',').first.trim(),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingTopicsCard(BuildContext context, bool isDark) {
    final topics = [
      {'tag': '#Technology', 'posts': '1.2k posts'},
      {'tag': '#Communities', 'posts': '840 posts'},
      {'tag': '#Design', 'posts': '650 posts'},
      {'tag': '#Startups', 'posts': '490 posts'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 18,
                color: Color(0xFFCE5DE5),
              ),
              const SizedBox(width: 8),
              Text(
                'Explore Topics',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...topics.map(
            (t) => InkWell(
              onTap: () => widget.onTabSelected(2),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t['tag']!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t['posts']!,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: context.textMuted.withValues(alpha: 0.7),
          decoration: TextDecoration.underline,
          decorationColor: context.textMuted.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
