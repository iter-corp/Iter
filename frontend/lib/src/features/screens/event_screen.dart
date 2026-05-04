import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/event_detail.dart';
import 'chat_screen.dart';

const _kBrandPurple = Color(0xFFB05ECC);
const _kBrandDeep = Color(0xFF8A3FB8);
const _kTagOrangeText = Color(0xFFD27B2B);

const List<String> _kPartnerFilters = [
  'All',
  'Nearby',
  'City',
  'Gender',
];

double? _distanceKm(dynamic a, dynamic b) {
  if (a is! Map || b is! Map) return null;
  final aLat = (a['lat'] as num?)?.toDouble();
  final aLng = (a['lng'] as num?)?.toDouble();
  final bLat = (b['lat'] as num?)?.toDouble();
  final bLng = (b['lng'] as num?)?.toDouble();
  if (aLat == null || aLng == null || bLat == null || bLng == null) {
    return null;
  }
  const r = 6371.0;
  final dLat = _toRad(bLat - aLat);
  final dLng = _toRad(bLng - aLng);
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final h = sinLat * sinLat +
      math.cos(_toRad(aLat)) * math.cos(_toRad(bLat)) * sinLng * sinLng;
  return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _toRad(double d) => d * math.pi / 180;

enum _MainTab { partners, events }

enum _EventsLayout { list, map }

String _eventCity(AdminEvent e) {
  final loc = e.location.trim();
  if (loc.isEmpty) return '';
  return loc.split(',').first.trim();
}

final _partnersStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .limit(300)
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = d.data();
            data['__id'] = d.id;
            return data;
          }).toList());
});

class EventBody extends ConsumerStatefulWidget {
  const EventBody({super.key});

  @override
  ConsumerState<EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<EventBody> {
  _MainTab _mainTab = _MainTab.partners;
  int _partnerFilter = 0;
  String? _selectedCity;
  String? _selectedEventCity;
  _EventsLayout _eventsLayout = _EventsLayout.list;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setTab(_MainTab tab) {
    if (tab == _mainTab) return;
    setState(() {
      _mainTab = tab;
      _searchController.clear();
    });
    if (tab == _MainTab.events) {
      _maybeShowEventsQuickStart();
    }
  }

  Future<void> _maybeShowEventsQuickStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('events_quickstart_seen') ?? false) return;
    if (!mounted) return;
    await prefs.setBool('events_quickstart_seen', true);
    if (!mounted) return;
    await showTravelQuickStartSheet(context);
  }

  Future<void> _onEventCityTap(List<AdminEvent> events) async {
    final cities = events
        .map(_eventCity)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (cities.isEmpty) return;
    final chosen = await _pickFromSheet(
      title: 'Filter events by city',
      options: cities,
      selected: _selectedEventCity,
    );
    if (chosen == null) return;
    setState(() => _selectedEventCity = chosen.isEmpty ? null : chosen);
  }

  Future<void> _onPartnerFilterTap(int i) async {
    if (i == 2) {
      final users = ref.read(_partnersStreamProvider).valueOrNull ?? const [];
      final cities = users
          .map((u) => (u['city'] as String? ?? '').trim())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() => _partnerFilter = 2);
      if (cities.isEmpty) return;
      final chosen = await _pickFromSheet(
        title: 'Filter by city',
        options: cities,
        selected: _selectedCity,
      );
      if (chosen == null) return; // dismissed
      setState(() => _selectedCity = chosen.isEmpty ? null : chosen);
    } else {
      setState(() => _partnerFilter = i);
    }
  }

  Future<String?> _pickFromSheet({
    required String title,
    required List<String> options,
    required String? selected,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _PickerSheet(
          title: title,
          options: options,
          selected: selected,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MainToggle(active: _mainTab, onChanged: _setTab),
                  const SizedBox(height: 14),
                  _SearchBar(
                    controller: _searchController,
                    hint: _mainTab == _MainTab.partners
                        ? 'Search people'
                        : 'Search events',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: _mainTab == _MainTab.partners
                    ? _PartnersView(
                        key: const ValueKey('partners'),
                        query: _query,
                        filterIndex: _partnerFilter,
                        selectedCity: _selectedCity,
                        onFilterTap: _onPartnerFilterTap,
                      )
                    : _EventsView(
                        key: const ValueKey('events'),
                        query: _query,
                        selectedCity: _selectedEventCity,
                        layout: _eventsLayout,
                        onCityTap: _onEventCityTap,
                        onClearCity: () =>
                            setState(() => _selectedEventCity = null),
                        onLayoutChanged: (l) =>
                            setState(() => _eventsLayout = l),
                        onShowQuickStart: () =>
                            showTravelQuickStartSheet(context),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Main segmented toggle: Connect / Events
// ─────────────────────────────────────────────────────────
class _MainToggle extends StatelessWidget {
  final _MainTab active;
  final ValueChanged<_MainTab> onChanged;
  const _MainToggle({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 4.0;
        final innerWidth = constraints.maxWidth - padding * 2;
        final pillWidth = innerWidth / 2;
        final isPartners = active == _MainTab.partners;
        return Container(
          height: 48,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.borderColor),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment:
                    isPartners ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: pillWidth,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kBrandPurple, _kBrandDeep],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _kBrandPurple.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ToggleItem(
                      label: 'Connect',
                      icon: Icons.people_alt_rounded,
                      active: isPartners,
                      onTap: () => onChanged(_MainTab.partners),
                    ),
                  ),
                  Expanded(
                    child: _ToggleItem(
                      label: 'Events',
                      icon: Icons.event_rounded,
                      active: !isPartners,
                      onTap: () => onChanged(_MainTab.events),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            color: active ? Colors.white : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? Colors.white : context.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Search bar
// ─────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _SearchBar({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20, color: _kBrandPurple),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                hintText: hint,
                hintStyle:
                    TextStyle(fontSize: 14, color: context.textSecondary),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(fontSize: 14, color: context.textPrimary),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: controller.clear,
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: context.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Partners view
// ─────────────────────────────────────────────────────────
class _PartnersView extends ConsumerWidget {
  final String query;
  final int filterIndex;
  final String? selectedCity;
  final ValueChanged<int> onFilterTap;

  const _PartnersView({
    super.key,
    required this.query,
    required this.filterIndex,
    required this.selectedCity,
    required this.onFilterTap,
  });

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> users,
    String currentUid,
    Map<String, dynamic>? currentUser,
  ) {
    final myBlocked = List<String>.from(currentUser?['blockedUsers'] ?? []);
    final q = query.toLowerCase();
    final filtered = users.where((u) {
      if (u['__id'] == currentUid) return false;

      // Filter out users I've blocked
      if (myBlocked.contains(u['__id'])) return false;

      // Filter out users who have blocked me
      final theirBlocked = List<String>.from(u['blockedUsers'] ?? []);
      if (theirBlocked.contains(currentUid)) return false;

      if (q.isEmpty) return true;
      final name = (u['username'] as String? ?? '').toLowerCase();
      final handle = (u['handle'] as String? ?? '').toLowerCase();
      final bio = (u['bio'] as String? ?? '').toLowerCase();
      final city = (u['city'] as String? ?? '').toLowerCase();
      return name.contains(q) ||
          handle.contains(q) ||
          bio.contains(q) ||
          city.contains(q);
    }).toList();

    switch (filterIndex) {
      case 1: // Nearby
        final withLoc = filtered.where((u) => u['location'] is Map).toList();
        final myLoc = currentUser?['location'];
        if (myLoc is Map) {
          withLoc.sort((a, b) {
            final dA = _distanceKm(myLoc, a['location']) ?? double.infinity;
            final dB = _distanceKm(myLoc, b['location']) ?? double.infinity;
            return dA.compareTo(dB);
          });
        }
        return withLoc;
      case 2: // City
        final pick = selectedCity?.toLowerCase().trim();
        if (pick == null || pick.isEmpty) {
          return filtered
              .where((u) => (u['city'] as String? ?? '').isNotEmpty)
              .toList();
        }
        return filtered
            .where((u) =>
                (u['city'] as String? ?? '').toLowerCase().trim() == pick)
            .toList();
      default:
        return filtered;
    }
  }

  IconData _emptyIcon(int i) {
    switch (i) {
      case 1:
        return Icons.near_me_outlined;
      case 2:
        return Icons.location_city_outlined;
      default:
        return Icons.search_off_rounded;
    }
  }

  String _emptySubtitle(int i) {
    switch (i) {
      case 1:
        return 'No one nearby yet — invite someone around you.';
      case 2:
        return 'No one from your city has joined yet.';
      default:
        return 'Be the first to say hi — invite someone.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_partnersStreamProvider);
    final currentUid = ref.watch(authStateProvider).value?.uid ?? '';
    final currentUserDoc = ref.watch(currentUserDocProvider).valueOrNull;

    final chipLabels = <String>[
      'All',
      'Nearby',
      selectedCity ?? 'City',
    ];

    return Column(
      children: [
        _FilterChipRow(
          active: filterIndex,
          labels: chipLabels,
          dropdownIndices: const {2},
          onTap: onFilterTap,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: usersAsync.when(
            loading: () => const _LoadingList(),
            error: (e, _) => _EmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: '$e',
            ),
            data: (users) {
              final results = _filter(users, currentUid, currentUserDoc);
              if (results.isEmpty) {
                final filterName = _kPartnerFilters[filterIndex].toLowerCase();
                return _EmptyState(
                  icon: _emptyIcon(filterIndex),
                  title: query.isEmpty
                      ? (filterIndex == 0
                          ? 'No people yet'
                          : 'No $filterName right now')
                      : 'No results for "$query"',
                  subtitle: query.isEmpty
                      ? _emptySubtitle(filterIndex)
                      : 'Try a different keyword or filter.',
                );
              }
              return RefreshIndicator(
                color: _kBrandPurple,
                onRefresh: () async {
                  ref.invalidate(_partnersStreamProvider);
                  await Future.delayed(const Duration(milliseconds: 400));
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final u = results[i];
                    return _PartnerCard(
                      uid: u['__id'] as String,
                      username: (u['username'] as String?) ?? 'User',
                      handle: (u['handle'] as String?) ?? '',
                      avatarUrl: u['avatarUrl'] as String?,
                      bio: (u['bio'] as String?) ?? '',
                      postsCount: (u['postsCount'] as int?) ?? 0,
                      createdAt: (u['createdAt'] as Timestamp?)?.toDate(),
                      city: (u['city'] as String?) ?? '',
                      gender: (u['gender'] as String?) ?? '',
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  final int active;
  final List<String> labels;
  final Set<int> dropdownIndices;
  final ValueChanged<int> onTap;
  const _FilterChipRow({
    required this.active,
    required this.labels,
    required this.dropdownIndices,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == active;
          final isDropdown = dropdownIndices.contains(i);
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? _kBrandPurple : context.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? _kBrandPurple : context.borderColor,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _kBrandPurple.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[i],
                    style: TextStyle(
                      color: selected ? Colors.white : context.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.1,
                    ),
                  ),
                  if (isDropdown) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: selected ? Colors.white : context.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PartnerCard extends ConsumerStatefulWidget {
  final String uid;
  final String username;
  final String handle;
  final String? avatarUrl;
  final String bio;
  final int postsCount;
  final DateTime? createdAt;
  final String city;
  final String gender;

  const _PartnerCard({
    required this.uid,
    required this.username,
    required this.handle,
    required this.avatarUrl,
    required this.bio,
    required this.postsCount,
    required this.createdAt,
    required this.city,
    required this.gender,
  });

  @override
  ConsumerState<_PartnerCard> createState() => _PartnerCardState();
}

class _PartnerCardState extends ConsumerState<_PartnerCard> {
  bool _sending = false;
  bool _pressed = false;

  Future<void> _wave() async {
    if (_sending) return;
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;
    setState(() => _sending = true);
    try {
      final chatId = await ref.read(chatServiceProvider).openChat(
            currentUid: currentUid,
            otherUid: widget.uid,
          );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUid: widget.uid,
            otherName: widget.username,
            otherAvatar: widget.avatarUrl ?? '',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _joinedAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'Joined just now';
    if (diff.inHours < 24) return 'Joined ${diff.inHours}h ago';
    if (diff.inDays < 30) return 'Joined ${diff.inDays}d ago';
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return 'Joined ${months}mo ago';
    }
    final years = (diff.inDays / 365).floor();
    return 'Joined ${years}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final presenceAsync = ref.watch(presenceWatchProvider(widget.uid));
    final isOnline = presenceAsync.whenOrNull(data: (p) => p.online) ?? false;
    final joined = _joinedAgo(widget.createdAt);

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () => openUserProfile(context, uid: widget.uid),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isOnline
                              ? const LinearGradient(
                                  colors: [_kBrandPurple, _kBrandDeep],
                                )
                              : null,
                          border: isOnline
                              ? null
                              : Border.all(
                                  color: context.borderColor, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFFF0F0F5),
                          backgroundImage: widget.avatarUrl != null
                              ? CachedNetworkImageProvider(widget.avatarUrl!)
                              : null,
                          child: widget.avatarUrl == null
                              ? Icon(Icons.person, color: context.textMuted)
                              : null,
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3BD671),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: context.cardBg, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? const Color(0xFF3BD671)
                                    : context.textSecondary
                                        .withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                isOnline ? 'Active now' : joined,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isOnline
                                      ? const Color(0xFF3BD671)
                                      : context.textSecondary,
                                  fontWeight: isOnline
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _WaveButton(busy: _sending, onTap: _wave),
                ],
              ),
              if (widget.bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (widget.city.isNotEmpty ||
                  widget.gender.isNotEmpty ||
                  widget.postsCount > 0) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (widget.city.isNotEmpty)
                      _Tag(label: widget.city, icon: Icons.location_on_rounded),
                    if (widget.gender.isNotEmpty) _Tag(label: widget.gender),
                    if (widget.postsCount > 0)
                      _Tag(label: '${widget.postsCount} posts'),
                    if (widget.postsCount >= 3)
                      const _Tag(label: 'Very active'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _WaveButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 54,
        height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kBrandPurple, _kBrandDeep],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _kBrandPurple.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.waving_hand_rounded,
                color: Colors.white,
                size: 21,
              ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _Tag({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.tagBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: _kTagOrangeText),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              color: _kTagOrangeText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Events view
// ─────────────────────────────────────────────────────────
class _EventsView extends ConsumerWidget {
  final String query;
  final String? selectedCity;
  final _EventsLayout layout;
  final ValueChanged<List<AdminEvent>> onCityTap;
  final VoidCallback onClearCity;
  final ValueChanged<_EventsLayout> onLayoutChanged;
  final VoidCallback onShowQuickStart;

  const _EventsView({
    super.key,
    required this.query,
    required this.selectedCity,
    required this.layout,
    required this.onCityTap,
    required this.onClearCity,
    required this.onLayoutChanged,
    required this.onShowQuickStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(adminEventsProvider);
    return eventsAsync.when(
      loading: () => const _LoadingGrid(),
      error: (e, _) => _EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: '$e',
      ),
      data: (events) {
        final q = query.toLowerCase();
        final cityPick = selectedCity?.toLowerCase().trim();
        final filtered = events.where((e) {
          if (q.isNotEmpty) {
            final inText = e.title.toLowerCase().contains(q) ||
                e.subtitle.toLowerCase().contains(q) ||
                e.location.toLowerCase().contains(q) ||
                e.description.toLowerCase().contains(q);
            if (!inText) return false;
          }
          if (cityPick != null && cityPick.isNotEmpty) {
            if (_eventCity(e).toLowerCase() != cityPick) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            _EventFilterBar(
              selectedCity: selectedCity,
              layout: layout,
              onCityTap: () => onCityTap(events),
              onClearCity: onClearCity,
              onLayoutChanged: onLayoutChanged,
              onShowQuickStart: onShowQuickStart,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.event_busy_outlined,
                      title: q.isEmpty && (cityPick == null || cityPick.isEmpty)
                          ? 'No events yet'
                          : (q.isNotEmpty
                              ? 'No events matching "$query"'
                              : 'No events in $selectedCity'),
                      subtitle: q.isEmpty &&
                              (cityPick == null || cityPick.isEmpty)
                          ? 'New events will appear here when posted.'
                          : 'Try a different keyword or location.',
                    )
                  : layout == _EventsLayout.map
                      ? _EventsMapView(events: filtered)
                      : RefreshIndicator(
                          color: _kBrandPurple,
                          onRefresh: () async {
                            ref.invalidate(adminEventsProvider);
                            await Future.delayed(
                                const Duration(milliseconds: 400));
                          },
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            slivers: [
                              const SliverToBoxAdapter(
                                  child: _BecomeAdminBanner()),
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 120),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.78,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) =>
                                        _EventCard(event: filtered[i]),
                                    childCount: filtered.length,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

// Event filter bar: city chip, list/map toggle, quick-start help.
class _EventFilterBar extends StatelessWidget {
  final String? selectedCity;
  final _EventsLayout layout;
  final VoidCallback onCityTap;
  final VoidCallback onClearCity;
  final ValueChanged<_EventsLayout> onLayoutChanged;
  final VoidCallback onShowQuickStart;

  const _EventFilterBar({
    required this.selectedCity,
    required this.layout,
    required this.onCityTap,
    required this.onClearCity,
    required this.onLayoutChanged,
    required this.onShowQuickStart,
  });

  @override
  Widget build(BuildContext context) {
    final cityActive = selectedCity != null && selectedCity!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onCityTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cityActive ? _kBrandPurple : context.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: cityActive ? _kBrandPurple : context.borderColor,
                  ),
                  boxShadow: cityActive
                      ? [
                          BoxShadow(
                            color: _kBrandPurple.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: cityActive ? Colors.white : _kBrandPurple,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cityActive ? selectedCity! : 'Filter by city',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              cityActive ? Colors.white : context.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (cityActive)
                      GestureDetector(
                        onTap: onClearCity,
                        child: const Icon(Icons.close_rounded,
                            size: 15, color: Colors.white),
                      )
                    else
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18, color: context.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LayoutToggle(layout: layout, onChanged: onLayoutChanged),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onShowQuickStart,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderColor),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: _kBrandPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  final _EventsLayout layout;
  final ValueChanged<_EventsLayout> onChanged;
  const _LayoutToggle({required this.layout, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _layoutButton(
            icon: Icons.grid_view_rounded,
            active: layout == _EventsLayout.list,
            onTap: () => onChanged(_EventsLayout.list),
          ),
          _layoutButton(
            icon: Icons.map_outlined,
            active: layout == _EventsLayout.map,
            onTap: () => onChanged(_EventsLayout.map),
          ),
        ],
      ),
    );
  }

  Widget _layoutButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 32,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [_kBrandPurple, _kBrandDeep],
                )
              : null,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 17,
          color: active ? Colors.white : const Color(0xFF8A8A92),
        ),
      ),
    );
  }
}

class _BecomeAdminBanner extends ConsumerWidget {
  const _BecomeAdminBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final email = cfg?.contactEmail ?? '';
    if (email.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Material(
        color: context.purpleSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showContactSheet(context, email),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kBrandPurple.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: _kBrandPurple,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Want to host your own event?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to contact our admin team.',
                        style: TextStyle(
                            fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFFB1B1B6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContactSheet(BuildContext context, String email) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Become an event admin',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Email us with your name, a short description of the event you\'d like to host, and why. We\'ll get back to you.',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.inputFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        email,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: email));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Email copied')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatefulWidget {
  final AdminEvent event;
  const _EventCard({required this.event});

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool _pressed = false;

  void _open() {
    final e = widget.event;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: e.id,
          title: e.title,
          subtitle: e.subtitle,
          location: e.location,
          imageUrls: e.imageUrls,
          description: e.description,
          phone: e.phone,
          email: e.email,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final coverUrl = e.imageUrls.isNotEmpty ? e.imageUrls.first : null;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _open,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null)
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: const Color(0xFFE0E0E8)),
                    errorWidget: (_, __, ___) =>
                        Container(color: const Color(0xFFBDBDBD)),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kBrandPurple, _kBrandDeep],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.event_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.3, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.78),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: context.cardBg.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 12,
                          color: _kBrandDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          e.location.split(',').first,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (e.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          e.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kBrandPurple, _kBrandDeep],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'See more',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Loading skeletons + empty state
// ─────────────────────────────────────────────────────────
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const _ShimmerBlock(height: 112),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => const _ShimmerBlock(radius: 22),
    );
  }
}

class _ShimmerBlock extends StatefulWidget {
  final double? height;
  final double radius;
  const _ShimmerBlock({this.height, this.radius = 20});

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
              colors: [
                context.inputFill,
                context.surfaceSoft,
                context.inputFill,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Bottom-sheet picker (used for City & Gender filters)
// ─────────────────────────────────────────────────────────
class _PickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selected;
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final v = _search.text.trim().toLowerCase();
      if (v != _q) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(_q)).toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (widget.selected != null)
                      TextButton(
                        onPressed: () => Navigator.pop(context, ''),
                        style: TextButton.styleFrom(
                          foregroundColor: _kBrandPurple,
                        ),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18, color: context.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Search',
                            hintStyle: TextStyle(
                                fontSize: 13, color: context.textSecondary),
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                              fontSize: 13, color: context.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No matches',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 20, endIndent: 20),
                        itemBuilder: (context, i) {
                          final opt = filtered[i];
                          final isSel = opt == widget.selected;
                          return ListTile(
                            onTap: () => Navigator.pop(context, opt),
                            title: Text(
                              opt,
                              style: TextStyle(
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                                color: context.textPrimary,
                              ),
                            ),
                            trailing: isSel
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: _kBrandPurple,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kBrandPurple.withValues(alpha: 0.18),
                    _kBrandDeep.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: _kBrandPurple),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Events map view — geocodes each event's location string and
// drops a pin at the resolved coordinate.
// ─────────────────────────────────────────────────────────

// Process-wide cache so we don't re-hit the geocoder when the user
// flips between list and map.
final Map<String, LatLng?> _eventGeocodeCache = {};

class _EventsMapView extends StatefulWidget {
  final List<AdminEvent> events;
  const _EventsMapView({required this.events});

  @override
  State<_EventsMapView> createState() => _EventsMapViewState();
}

class _EventsMapViewState extends State<_EventsMapView> {
  final Map<String, LatLng> _resolved = {};
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolveAll();
  }

  @override
  void didUpdateWidget(covariant _EventsMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveAll();
  }

  Future<void> _resolveAll() async {
    if (_resolving) return;
    _resolving = true;
    for (final e in widget.events) {
      final loc = e.location.trim();
      if (loc.isEmpty) continue;
      if (_resolved.containsKey(e.id)) continue;
      final cached = _eventGeocodeCache[loc];
      if (_eventGeocodeCache.containsKey(loc)) {
        if (cached != null) {
          _resolved[e.id] = cached;
        }
        continue;
      }
      try {
        final results = await geo.locationFromAddress(loc);
        if (results.isNotEmpty) {
          final p = LatLng(results.first.latitude, results.first.longitude);
          _eventGeocodeCache[loc] = p;
          _resolved[e.id] = p;
        } else {
          _eventGeocodeCache[loc] = null;
        }
      } catch (_) {
        _eventGeocodeCache[loc] = null;
      }
      if (mounted) setState(() {});
    }
    _resolving = false;
  }

  LatLng _initialCenter() {
    if (_resolved.isEmpty) {
      // Fallback: roughly centered on Europe / Africa so the empty world
      // doesn't open zoomed on the wrong hemisphere.
      return const LatLng(20, 10);
    }
    double sumLat = 0, sumLng = 0;
    for (final p in _resolved.values) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / _resolved.length, sumLng / _resolved.length);
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final e in widget.events) {
      final p = _resolved[e.id];
      if (p == null) continue;
      markers.add(
        Marker(
          point: p,
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _showEventSheet(context, e),
            child: const _EventMapPin(),
          ),
        ),
      );
    }

    final unresolved = widget.events.length - markers.length;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: markers.length > 1 ? 4 : 11,
            minZoom: 2,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.coil.app',
            ),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (unresolved > 0)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _resolving
                          ? 'Locating $unresolved event${unresolved == 1 ? '' : 's'}...'
                          : '$unresolved event${unresolved == 1 ? '' : 's'} could not be mapped',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showEventSheet(BuildContext context, AdminEvent e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventMapSheet(event: e),
    );
  }
}

class _EventMapPin extends StatelessWidget {
  const _EventMapPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _kBrandPurple,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.event_rounded, color: Colors.white, size: 18),
    );
  }
}

class _EventMapSheet extends StatelessWidget {
  final AdminEvent event;
  const _EventMapSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    final cover = event.imageUrls.isNotEmpty ? event.imageUrls.first : null;
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: cover != null
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_kBrandPurple, _kBrandDeep],
                          ),
                        ),
                        child: const Icon(Icons.event_rounded,
                            color: Colors.white),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 13, color: _kBrandPurple),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventDetailScreen(
                      eventId: event.id,
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
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('View event'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrandPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Travel Mode Quick-Start sheet
// Shown on first-ever entry to the Events tab; reachable
// later via the (?) help button next to the filter.
// ─────────────────────────────────────────────────────────
Future<void> showTravelQuickStartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _TravelQuickStartSheet(),
  );
}

class _TravelQuickStartSheet extends StatelessWidget {
  const _TravelQuickStartSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kBrandPurple, _kBrandDeep],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.travel_explore_rounded,
                          color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Travel Mode',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Quick start guide',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const _QuickStartStep(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Switch to Travel feed',
                  body:
                      'On Home, tap the Travel toggle to see posts from people in other places — not just the ones you follow.',
                ),
                const _QuickStartStep(
                  icon: Icons.location_on_rounded,
                  title: 'Filter by city',
                  body:
                      'In Events, tap "Filter by city" to narrow events down to a specific destination.',
                ),
                const _QuickStartStep(
                  icon: Icons.map_outlined,
                  title: 'See events on a map',
                  body:
                      'Use the map toggle next to the city filter to drop pins for every event and tap any pin to preview it.',
                ),
                const _QuickStartStep(
                  icon: Icons.flight_takeoff_rounded,
                  title: 'Plan your trip',
                  body:
                      'Open any event and use the Hotels and Flights shortcuts to start planning before you go.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickStartStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _QuickStartStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kBrandPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kBrandPurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: context.textSecondary,
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
