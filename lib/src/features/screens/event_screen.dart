import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/admin_service.dart';
import '../../services/city_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/maps_links.dart';
import '../widgets/app_page_background.dart';
import '../widgets/event_detail.dart';
import 'chat_screen.dart';

const _kBrandPurple = Color(0xFFB05ECC);
const _kBrandDeep = Color(0xFF8A3FB8);
const _kTagOrangeText = Color(0xFFD27B2B);

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

/// Heuristic relevance of [e] to the signed-in [userDoc] (null = no profile).
/// Higher = more relevant. Used to surface "For you" events and order the grid.
int _eventRelevanceScore(AdminEvent e, Map<String, dynamic>? userDoc) {
  if (userDoc == null) return 0;
  var score = 0;

  final field = (userDoc['field'] as String? ?? '').trim().toLowerCase();
  final goals = ((userDoc['goals'] as List?)?.cast<String>() ?? const [])
      .map((g) => g.toLowerCase())
      .toList();
  final userCity = (userDoc['city'] as String? ?? '').trim().toLowerCase();
  final userLoc = userDoc['location'];
  final userLat = userLoc is Map ? (userLoc['lat'] as num?)?.toDouble() : null;
  final userLng = userLoc is Map ? (userLoc['lng'] as num?)?.toDouble() : null;

  final haystack =
      '${e.title} ${e.subtitle} ${e.description} ${e.eventType}'.toLowerCase();

  if (field.isNotEmpty && haystack.contains(field)) score += 3;
  for (final g in goals) {
    if (g.isNotEmpty && haystack.contains(g)) score += 2;
  }
  // Goal → event-type affinity (e.g. "Conferences" goal ↔ Conference type).
  final type = e.eventType.trim().toLowerCase();
  if (type.isNotEmpty) {
    if (goals.any((g) => type.contains(g) || g.contains(type))) score += 2;
  }
  if (userCity.isNotEmpty && _eventCity(e).toLowerCase() == userCity)
    score += 2;
  if (userLat != null && userLng != null && e.lat != null && e.lng != null) {
    final km = _distanceKm(
      {'lat': userLat, 'lng': userLng},
      {'lat': e.lat, 'lng': e.lng},
    );
    if (km != null && km <= 100) score += 1;
  }
  return score;
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
  _MainTab _mainTab = _MainTab.events;
  String? _selectedCity;
  bool _nearbyMode = false;
  String? _selectedField;
  String? _selectedAcademicLevel;
  String? _selectedEventCity;
  String? _selectedEventType;
  _EventsLayout _eventsLayout = _EventsLayout.list;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mainTab == _MainTab.events) {
        _maybeShowEventsQuickStart();
      }
    });
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
    // Scope the "seen" flag by uid so each user sees the quick-start exactly
    // once, even if multiple accounts use the same device. The old key was
    // device-wide so users B, C... never got the guide after user A had
    // dismissed it, and a new user on a freshly-installed app would still
    // see it. Falls back to a `_anon` bucket only if no user is signed in.
    final uid = ref.read(authStateProvider).value?.uid ?? '_anon';
    final prefKey = 'events_quickstart_seen_$uid';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefKey) ?? false) return;
    if (!mounted) return;
    await prefs.setBool(prefKey, true);
    if (!mounted) return;
    await showEventsQuickStartSheet(context);
  }

  Future<void> _onEventCityTap(List<AdminEvent> events) async {
    // Tapping the chip while a country is active clears the filter.
    if (_selectedEventCity != null) {
      setState(() => _selectedEventCity = null);
      return;
    }
    final configCountries =
        ref.read(adminConfigProvider).valueOrNull?.eventCountries;
    final eventCountries = {
      ...?configCountries,
      ...events.map((e) => e.country).where((c) => c.trim().isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final chosen = await _pickFromSheet(
      title: context.t.adminChooseCountry,
      options: eventCountries.isEmpty ? kEventCountries : eventCountries,
      selected: _selectedEventCity,
    );
    if (chosen == null) return;
    setState(() => _selectedEventCity = chosen.isEmpty ? null : chosen);
  }

  Future<void> _onEventTypeTap() async {
    final chosen = await _pickFromSheet(
      title: context.t.eventsFilterByType,
      options: kEventTypes,
      selected: _selectedEventType,
    );
    if (chosen == null) return;
    setState(() => _selectedEventType = chosen.isEmpty ? null : chosen);
  }

  Future<void> _onPartnerFilterTap(int i) async {
    final users = ref.read(_partnersStreamProvider).valueOrNull ?? const [];

    if (i == 0) {
      // All — clear every filter
      setState(() {
        _nearbyMode = false;
        _selectedCity = null;
        _selectedField = null;
        _selectedAcademicLevel = null;
      });
    } else if (i == 1) {
      // City filter - deselect if already active
      if (_nearbyMode || _selectedCity != null) {
        setState(() {
          _nearbyMode = false;
          _selectedCity = null;
        });
        return;
      }

      // Open the world-city picker directly; "Nearby" is a pinned row
      // at the top of the same list.
      final chosen = await showCityPicker(context, showNearby: true);
      if (chosen == null || chosen.isEmpty) return;

      if (chosen == kCityPickerNearby) {
        setState(() {
          _nearbyMode = true;
          _selectedCity = null;
        });
      } else {
        setState(() {
          _nearbyMode = false;
          _selectedCity = chosen;
        });
      }
    } else if (i == 2) {
      // Field filter - deselect if already active
      if (_selectedField != null) {
        setState(() => _selectedField = null);
        return;
      }

      final fields = users
          .map((u) => (u['field'] as String? ?? '').trim())
          .where((f) => f.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (fields.isEmpty) return;

      final chosen = await _pickFromSheet(
        title: context.t.eventsFilterByField,
        options: fields,
        selected: _selectedField,
      );
      if (chosen == null) return;
      setState(() => _selectedField = chosen.isEmpty ? null : chosen);
    } else if (i == 3) {
      // Academic Level filter - deselect if already active
      if (_selectedAcademicLevel != null) {
        setState(() => _selectedAcademicLevel = null);
        return;
      }

      final levels = users
          .map((u) => (u['academicLevel'] as String? ?? '').trim())
          .where((l) => l.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (levels.isEmpty) return;

      final chosen = await _pickFromSheet(
        title: context.t.eventsFilterByAcademicLevel,
        options: levels,
        selected: _selectedAcademicLevel,
      );
      if (chosen == null) return;
      setState(() => _selectedAcademicLevel = chosen.isEmpty ? null : chosen);
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
      backgroundColor: Colors.transparent,
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
                    if (_mainTab == _MainTab.events)
                      Row(
                        children: [
                          Expanded(
                            child: _SearchBar(
                              controller: _searchController,
                              hint: context.t.eventsSearchEvents,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _LayoutToggle(
                            layout: _eventsLayout,
                            onChanged: (l) => setState(() => _eventsLayout = l),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => showEventsQuickStartSheet(context),
                            child: AppGlassCard(
                              width: 38,
                              height: 38,
                              radius: 19,
                              surfaceAlpha: context.isDark ? 0.24 : 0.52,
                              borderAlpha: context.isDark ? 0.16 : 0.50,
                              child: const Icon(
                                Icons.help_outline_rounded,
                                size: 18,
                                color: _kBrandPurple,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      _SearchBar(
                        controller: _searchController,
                        hint: context.t.eventsSearchPeople,
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
                          selectedCity: _selectedCity,
                          nearbyMode: _nearbyMode,
                          selectedField: _selectedField,
                          selectedAcademicLevel: _selectedAcademicLevel,
                          onFilterTap: _onPartnerFilterTap,
                        )
                      : _EventsView(
                          key: const ValueKey('events'),
                          query: _query,
                          selectedCity: _selectedEventCity,
                          selectedEventType: _selectedEventType,
                          layout: _eventsLayout,
                          onCityTap: _onEventCityTap,
                          onClearCity: () =>
                              setState(() => _selectedEventCity = null),
                          onTypeTap: _onEventTypeTap,
                          onClearType: () =>
                              setState(() => _selectedEventType = null),
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
        final isEvents = active == _MainTab.events;
        return AppGlassCard(
          height: 48,
          padding: const EdgeInsets.all(padding),
          radius: 28,
          surfaceAlpha: context.isDark ? 0.28 : 0.54,
          borderAlpha: context.isDark ? 0.18 : 0.52,
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: isEvents
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
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
                      label: context.t.events,
                      icon: Icons.event_rounded,
                      active: isEvents,
                      onTap: () => onChanged(_MainTab.events),
                    ),
                  ),
                  Expanded(
                    child: _ToggleItem(
                      label: context.t.eventsConnect,
                      icon: Icons.people_alt_rounded,
                      active: !isEvents,
                      onTap: () => onChanged(_MainTab.partners),
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
    return AppGlassCard(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      radius: 18,
      surfaceAlpha: context.isDark ? 0.24 : 0.52,
      borderAlpha: context.isDark ? 0.16 : 0.50,
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
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
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
  final String? selectedCity;
  final bool nearbyMode;
  final String? selectedField;
  final String? selectedAcademicLevel;
  final ValueChanged<int> onFilterTap;

  const _PartnersView({
    super.key,
    required this.query,
    required this.selectedCity,
    required this.nearbyMode,
    required this.selectedField,
    required this.selectedAcademicLevel,
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

    // Apply all active filters simultaneously
    var result = filtered;

    // City / Nearby filter
    if (nearbyMode) {
      result = result.where((u) => u['location'] is Map).toList();
      final myLoc = currentUser?['location'];
      if (myLoc is Map) {
        result.sort((a, b) {
          final dA = _distanceKm(myLoc, a['location']) ?? double.infinity;
          final dB = _distanceKm(myLoc, b['location']) ?? double.infinity;
          return dA.compareTo(dB);
        });
      }
    } else if (selectedCity != null && selectedCity!.isNotEmpty) {
      final pick = selectedCity!.toLowerCase().trim();
      result = result
          .where(
              (u) => (u['city'] as String? ?? '').toLowerCase().trim() == pick)
          .toList();
    }

    // Field filter
    if (selectedField != null && selectedField!.isNotEmpty) {
      final pick = selectedField!.toLowerCase().trim();
      result = result
          .where(
              (u) => (u['field'] as String? ?? '').toLowerCase().trim() == pick)
          .toList();
    }

    // Academic level filter
    if (selectedAcademicLevel != null && selectedAcademicLevel!.isNotEmpty) {
      final pick = selectedAcademicLevel!.toLowerCase().trim();
      result = result
          .where((u) =>
              (u['academicLevel'] as String? ?? '').toLowerCase().trim() ==
              pick)
          .toList();
    }

    return result;
  }

  bool get _hasActiveFilter =>
      nearbyMode ||
      (selectedCity?.isNotEmpty ?? false) ||
      (selectedField?.isNotEmpty ?? false) ||
      (selectedAcademicLevel?.isNotEmpty ?? false);

  IconData get _emptyIcon {
    if (nearbyMode) return Icons.near_me_outlined;
    if (selectedCity?.isNotEmpty ?? false) return Icons.location_city_outlined;
    if (selectedField?.isNotEmpty ?? false) return Icons.school_outlined;
    if (selectedAcademicLevel?.isNotEmpty ?? false)
      return Icons.trending_up_outlined;
    return Icons.search_off_rounded;
  }

  String _emptySubtitle(BuildContext context) {
    if (nearbyMode) return context.t.eventsNoOneNearby;
    if (selectedCity?.isNotEmpty ?? false) {
      return context.t.eventsNoOneFromCity;
    }
    if (selectedField?.isNotEmpty ?? false) {
      return context.t.eventsNoOneInField;
    }
    if (selectedAcademicLevel?.isNotEmpty ?? false) {
      return context.t.eventsNoOneAtAcademicLevel;
    }
    return context.t.eventsBeFirstSayHi;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_partnersStreamProvider);
    final currentUid = ref.watch(authStateProvider).value?.uid ?? '';
    final currentUserDoc = ref.watch(currentUserDocProvider).valueOrNull;

    final chipLabels = <String>[
      context.t.eventsFilterAll,
      nearbyMode
          ? context.t.eventsFilterNearby
          : (selectedCity ?? context.t.eventsFilterCity),
      selectedField ?? context.t.eventsFilterField,
      selectedAcademicLevel ?? context.t.eventsFilterLevel,
    ];

    final activeIndices = <int>{
      if (!_hasActiveFilter) 0,
      if (nearbyMode || (selectedCity?.isNotEmpty ?? false)) 1,
      if (selectedField?.isNotEmpty ?? false) 2,
      if (selectedAcademicLevel?.isNotEmpty ?? false) 3,
    };

    return Column(
      children: [
        _FilterChipRow(
          activeIndices: activeIndices,
          labels: chipLabels,
          dropdownIndices: const {1, 2, 3},
          onTap: onFilterTap,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: usersAsync.when(
            loading: () => const _LoadingList(),
            error: (e, _) => _EmptyState(
              icon: Icons.error_outline,
              title: context.t.somethingWentWrong,
              subtitle: '$e',
            ),
            data: (users) {
              final results = _filter(users, currentUid, currentUserDoc);
              if (results.isEmpty) {
                return _EmptyState(
                  icon: _emptyIcon,
                  title: query.isEmpty
                      ? (_hasActiveFilter
                          ? context.t.eventsNoMatchingPeople
                          : context.t.eventsNoPeopleYet)
                      : context.t.eventsNoResultsFor(query),
                  subtitle: query.isEmpty
                      ? _emptySubtitle(context)
                      : context.t.eventsTryDifferentKeyword,
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
                      field: u['field'] as String?,
                      profession: u['profession'] as String?,
                      academicLevel: u['academicLevel'] as String?,
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
  final Set<int> activeIndices;
  final List<String> labels;
  final Set<int> dropdownIndices;
  final ValueChanged<int> onTap;
  const _FilterChipRow({
    required this.activeIndices,
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
          final selected = activeIndices.contains(i);
          final isDropdown = dropdownIndices.contains(i);
          final child = Row(
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
                  selected
                      ? Icons.close_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: selected ? Colors.white : context.textSecondary,
                ),
              ],
            ],
          );
          return GestureDetector(
            onTap: () => onTap(i),
            child: selected
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kBrandPurple,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _kBrandPurple),
                      boxShadow: [
                        BoxShadow(
                          color: _kBrandPurple.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: child,
                  )
                : AppGlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    radius: 22,
                    surfaceAlpha: context.isDark ? 0.22 : 0.50,
                    borderAlpha: context.isDark ? 0.14 : 0.46,
                    child: child,
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
  final String? field;
  final String? profession;
  final String? academicLevel;

  const _PartnerCard({
    required this.uid,
    required this.username,
    required this.handle,
    required this.avatarUrl,
    required this.bio,
    required this.postsCount,
    required this.createdAt,
    required this.city,
    this.field,
    this.profession,
    this.academicLevel,
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
        SnackBar(content: Text(context.t.eventsFailedToOpenChat(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _joinedAgo(BuildContext context, DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return context.t.eventsJoinedJustNow;
    if (diff.inHours < 24) return context.t.eventsJoinedHoursAgo(diff.inHours);
    if (diff.inDays < 30) return context.t.eventsJoinedDaysAgo(diff.inDays);
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return context.t.eventsJoinedMonthsAgo(months);
    }
    final years = (diff.inDays / 365).floor();
    return context.t.eventsJoinedYearsAgo(years);
  }

  @override
  Widget build(BuildContext context) {
    final presenceAsync = ref.watch(presenceWatchProvider(widget.uid));
    final isOnline = presenceAsync.whenOrNull(data: (p) => p.online) ?? false;
    final joined = _joinedAgo(context, widget.createdAt);

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () => openUserProfile(context, uid: widget.uid),
        child: AppGlassCard(
          padding: const EdgeInsets.all(14),
          radius: 22,
          emphasize: isOnline,
          surfaceAlpha: context.isDark ? 0.24 : 0.52,
          borderAlpha: context.isDark ? 0.16 : 0.50,
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
                                isOnline ? context.t.eventsActiveNow : joined,
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
              if ((widget.field?.isNotEmpty ?? false) ||
                  (widget.profession?.isNotEmpty ?? false) ||
                  (widget.academicLevel?.isNotEmpty ?? false) ||
                  widget.city.isNotEmpty ||
                  widget.postsCount > 0) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Show field, profession, academic level if available
                    if (widget.field?.isNotEmpty ?? false)
                      _Tag(label: widget.field!),
                    if (widget.profession?.isNotEmpty ?? false)
                      _Tag(label: widget.profession!),
                    if (widget.academicLevel?.isNotEmpty ?? false)
                      _Tag(label: widget.academicLevel!),
                    // Show location as fallback if no field/profession/academic level
                    if ((widget.field?.isEmpty ?? true) &&
                        (widget.profession?.isEmpty ?? true) &&
                        (widget.academicLevel?.isEmpty ?? true) &&
                        widget.city.isNotEmpty)
                      _Tag(label: widget.city, icon: Icons.location_on_rounded),
                    if (widget.postsCount > 0)
                      _Tag(label: context.t.eventsPostsCount(widget.postsCount)),
                    if (widget.postsCount >= 3)
                      _Tag(label: context.t.eventsVeryActive),
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
    return AppGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      radius: 20,
      surfaceAlpha: context.isDark ? 0.20 : 0.44,
      borderAlpha: context.isDark ? 0.12 : 0.38,
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
  final String? selectedEventType;
  final _EventsLayout layout;
  final ValueChanged<List<AdminEvent>> onCityTap;
  final VoidCallback onClearCity;
  final VoidCallback onTypeTap;
  final VoidCallback onClearType;

  const _EventsView({
    super.key,
    required this.query,
    required this.selectedCity,
    required this.selectedEventType,
    required this.layout,
    required this.onCityTap,
    required this.onClearCity,
    required this.onTypeTap,
    required this.onClearType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(adminEventsProvider);
    final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
    return eventsAsync.when(
      loading: () => const _LoadingGrid(),
      error: (e, _) => _EmptyState(
        icon: Icons.error_outline,
        title: context.t.somethingWentWrong,
        subtitle: '$e',
      ),
      data: (events) {
        final q = query.toLowerCase();
        final cityPick = selectedCity?.toLowerCase().trim();
        final typePick = selectedEventType?.toLowerCase().trim();
        final filtered = events.where((e) {
          if (q.isNotEmpty) {
            final inText = e.title.toLowerCase().contains(q) ||
                e.subtitle.toLowerCase().contains(q) ||
                e.location.toLowerCase().contains(q) ||
                e.description.toLowerCase().contains(q) ||
                e.eventType.toLowerCase().contains(q);
            if (!inText) return false;
          }
          if (cityPick != null && cityPick.isNotEmpty) {
            if (e.country.trim().toLowerCase() != cityPick) return false;
          }
          if (typePick != null && typePick.isNotEmpty) {
            if (e.eventType.toLowerCase().trim() != typePick) return false;
          }
          return true;
        }).toList();

        final hasCityFilter = cityPick != null && cityPick.isNotEmpty;
        final hasTypeFilter = typePick != null && typePick.isNotEmpty;
        final hasAnyFilter = q.isNotEmpty || hasCityFilter || hasTypeFilter;

        // Personalized ordering: events that match the user's field / goals /
        // city / location bubble to the top with a "For you" badge. Stable
        // within each score bucket so newest-first is preserved otherwise.
        final scored = {
          for (final e in filtered) e.id: _eventRelevanceScore(e, userDoc),
        };
        filtered
            .sort((a, b) => (scored[b.id] ?? 0).compareTo(scored[a.id] ?? 0));

        return Column(
          children: [
            _EventFilterBar(
              selectedCity: selectedCity,
              selectedType: selectedEventType,
              onCityTap: () => onCityTap(events),
              onClearCity: onClearCity,
              onTypeTap: onTypeTap,
              onClearType: onClearType,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.event_busy_outlined,
                      title: !hasAnyFilter
                          ? context.t.noEvents
                          : (q.isNotEmpty
                              ? context.t.eventsNoEventsMatching(query)
                              : (hasCityFilter && hasTypeFilter
                                  ? context.t.eventsNoTypeEventsInCity(
                                      selectedEventType ?? '',
                                      selectedCity ?? '')
                                  : (hasCityFilter
                                      ? context.t.eventsNoEventsInCity(
                                          selectedCity ?? '')
                                      : context.t.eventsNoTypeEvents(
                                          selectedEventType ?? '')))),
                      subtitle: !hasAnyFilter
                          ? context.t.eventsNewEventsAppearHere
                          : context.t.eventsTryDifferentKeywordLocation,
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
                                    (context, i) => _EventCard(
                                      event: filtered[i],
                                      recommended:
                                          (scored[filtered[i].id] ?? 0) > 0,
                                    ),
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

// Event filter bar: city + type chips.
class _EventFilterBar extends StatelessWidget {
  final String? selectedCity;
  final String? selectedType;
  final VoidCallback onCityTap;
  final VoidCallback onClearCity;
  final VoidCallback onTypeTap;
  final VoidCallback onClearType;

  const _EventFilterBar({
    required this.selectedCity,
    required this.selectedType,
    required this.onCityTap,
    required this.onClearCity,
    required this.onTypeTap,
    required this.onClearType,
  });

  @override
  Widget build(BuildContext context) {
    final cityActive = selectedCity != null && selectedCity!.isNotEmpty;
    final typeActive = selectedType != null && selectedType!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: _EventFilterChip(
              active: cityActive,
              icon: Icons.location_on_rounded,
              label: cityActive ? selectedCity! : context.t.eventsFilterByCity,
              onTap: onCityTap,
              onClear: onClearCity,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _EventFilterChip(
              active: typeActive,
              icon: Icons.tune_rounded,
              label: typeActive ? selectedType! : context.t.eventsFilterByTypeChip,
              onTap: onTypeTap,
              onClear: onClearType,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventFilterChip extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _EventFilterChip({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(icon, size: 16, color: active ? Colors.white : _kBrandPurple),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? Colors.white : context.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        if (active)
          GestureDetector(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              size: 15,
              color: Colors.white,
            ),
          )
        else
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: context.textSecondary,
          ),
      ],
    );

    return GestureDetector(
      onTap: onTap,
      child: active
          ? AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kBrandPurple,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBrandPurple),
                boxShadow: [
                  BoxShadow(
                    color: _kBrandPurple.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: content,
            )
          : AppGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              radius: 22,
              surfaceAlpha: context.isDark ? 0.22 : 0.50,
              borderAlpha: context.isDark ? 0.14 : 0.46,
              child: content,
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
    return AppGlassCard(
      height: 38,
      padding: const EdgeInsets.all(3),
      radius: 20,
      surfaceAlpha: context.isDark ? 0.24 : 0.52,
      borderAlpha: context.isDark ? 0.16 : 0.50,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _layoutButton(
            context: context,
            icon: Icons.grid_view_rounded,
            active: layout == _EventsLayout.list,
            onTap: () => onChanged(_EventsLayout.list),
          ),
          _layoutButton(
            context: context,
            icon: Icons.map_outlined,
            active: layout == _EventsLayout.map,
            onTap: () => onChanged(_EventsLayout.map),
          ),
        ],
      ),
    );
  }

  Widget _layoutButton({
    required BuildContext context,
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
          size: 18,
          color: active ? Colors.white : context.textSecondary,
        ),
      ),
    );
  }
}


class _EventCard extends StatefulWidget {
  final AdminEvent event;
  final bool recommended;
  const _EventCard({required this.event, this.recommended = false});

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
          eventType: e.eventType,
          funds: e.funds,
          deadlineAt: e.deadlineAt,
          imageUrls: e.imageUrls,
          description: e.description,
          link: e.link,
          phone: e.phone,
          email: e.email,
          createdByUid: e.createdByUid,
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
                // Top-left stacked chips: city on top, then type ("Scholarship")
                // and the "For you" badge if recommended. Stacking vertically
                // gives each chip the full card width on the 2-column grid,
                // so long labels stay fully readable instead of ellipsizing.
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // City pill
                      Align(
                        alignment: AlignmentDirectional.centerStart,
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
                              Flexible(
                                child: Text(
                                  e.location.split(',').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (e.eventType.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: context.cardBg.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              e.eventType.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (widget.recommended) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_kBrandPurple, _kBrandDeep],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome_rounded,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(
                                  context.t.eventsForYou,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t.eventsSeeMore,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                          child: Text(context.t.clear),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: TextField(
                    controller: _search,
                    style: TextStyle(fontSize: 14, color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: context.t.search,
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: context.textSecondary,
                      ),
                      filled: true,
                      fillColor: context.surfaceSoft.withOpacity(0.45),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 10, right: 6),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _kBrandPurple,
                        ),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      suffixIcon: _q.isNotEmpty
                          ? IconButton(
                              tooltip: context.t.clearSearch,
                              onPressed: () {
                                _search.clear();
                                FocusScope.of(context).unfocus();
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: context.textSecondary,
                              ),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.06),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(
                          color: _kBrandPurple.withOpacity(0.55),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              context.t.noMatches,
                              style: TextStyle(color: context.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final opt = filtered[i];
                            final isSel = opt == widget.selected;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Material(
                                color: isSel
                                    ? _kBrandPurple.withOpacity(0.14)
                                    : context.surfaceSoft.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  onTap: () => Navigator.pop(context, opt),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  title: Text(
                                    opt,
                                    style: TextStyle(
                                      fontWeight: isSel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  trailing: isSel
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: _kBrandPurple,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 48),
            ),
            child: Center(
              child: AppGlassCard(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                radius: 24,
                surfaceAlpha: context.isDark ? 0.22 : 0.50,
                borderAlpha: context.isDark ? 0.14 : 0.48,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
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
                      child: Icon(icon, size: 34, color: _kBrandPurple),
                    ),
                    const SizedBox(height: 14),
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
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
      if (_resolved.containsKey(e.id)) continue;
      // Prefer the admin-set pin coordinates when present — no geocoding needed.
      if (e.lat != null && e.lng != null) {
        _resolved[e.id] = LatLng(e.lat!, e.lng!);
        if (mounted) setState(() {});
        continue;
      }
      final loc = e.location.trim();
      if (loc.isEmpty) continue;
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
            onTap: () => _showEventSheet(context, e, p),
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
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(context.t.mapAttributionLong),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _resolving
                          ? context.t.eventsLocatingEvents(unresolved)
                          : context.t.eventsCouldNotBeMapped(unresolved),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showEventSheet(BuildContext context, AdminEvent e, LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventMapSheet(event: e, point: point),
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
  final LatLng point;
  const _EventMapSheet({required this.event, required this.point});

  @override
  Widget build(BuildContext context) {
    final cover = event.imageUrls.isNotEmpty ? event.imageUrls.first : null;
    final type = event.eventType.trim();
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
                    if (type.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kBrandPurple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kBrandDeep,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => openDirectionsTo(
                    context,
                    lat: point.latitude,
                    lng: point.longitude,
                  ),
                  child: AppGlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    radius: 14,
                    surfaceAlpha: context.isDark ? 0.22 : 0.50,
                    borderAlpha: context.isDark ? 0.16 : 0.48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.directions_rounded,
                          size: 16,
                          color: _kBrandPurple,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.t.eventsDirections,
                          style: const TextStyle(
                            color: _kBrandPurple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
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
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(context.t.eventsViewEvent),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Events Quick-Start sheet
// Shown on first-ever entry to the Events tab; reachable
// later via the (?) help button next to the filter.
// ─────────────────────────────────────────────────────────
Future<void> showEventsQuickStartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _EventsQuickStartSheet(),
  );
}

class _EventsQuickStartSheet extends StatelessWidget {
  const _EventsQuickStartSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
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
              child: Row(
                children: [
                  const Icon(Icons.event_available_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t.events,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t.eventsQuickStartGuide,
                          style: const TextStyle(
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
            _QuickStartStep(
              icon: Icons.event_note_rounded,
              title: context.t.eventsSwitchTravelFeed,
              body: context.t.eventsSwitchTravelFeedBody,
            ),
            _QuickStartStep(
              icon: Icons.location_on_rounded,
              title: context.t.eventsFilterByCityStep,
              body: context.t.eventsFilterByCityStepBody,
            ),
            _QuickStartStep(
              icon: Icons.map_outlined,
              title: context.t.eventsSeeEventsOnMap,
              body: context.t.eventsSeeEventsOnMapBody,
            ),
            _QuickStartStep(
              icon: Icons.people_alt_rounded,
              title: context.t.eventsPlanYourTrip,
              body: context.t.eventsPlanYourTripBody,
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
                child: Text(
                  context.t.eventsGotIt,
                  style: const TextStyle(
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
