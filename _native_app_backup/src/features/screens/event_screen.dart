import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../services/admin_service.dart';
import '../../services/city_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/maps_links.dart';
import '../widgets/app_page_background.dart';
import '../widgets/event_detail.dart';

const _kBrandPurple = Color(0xFFB05ECC);
const _kBrandDeep = Color(0xFF8A3FB8);

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
  if (userCity.isNotEmpty && _eventCity(e).toLowerCase() == userCity) {
    score += 2;
  }
  if (userLat != null && userLng != null && e.lat != null && e.lng != null) {
    final km = _distanceKm(
      {'lat': userLat, 'lng': userLng},
      {'lat': e.lat, 'lng': e.lng},
    );
    if (km != null && km <= 100) score += 1;
  }
  return score;
}class EventBody extends ConsumerStatefulWidget {
  const EventBody({super.key});

  @override
  ConsumerState<EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<EventBody>
    with SingleTickerProviderStateMixin {
  String? _selectedEventCity;
  String? _selectedEventType;
  _EventsLayout _eventsLayout = _EventsLayout.list;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final AnimationController _searchAnimController;
  late final Animation<double> _searchAnim;
  bool _isSearchOpen = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _searchAnim = CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowEventsQuickStart();
    });
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
    _searchAnimController.forward().then((_) {
      if (mounted && _isSearchOpen) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    _searchAnimController.reverse().then((_) {
      if (mounted) setState(() => _isSearchOpen = false);
    });
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

  Future<void> _onEventCityTap([List<AdminEvent>? eventsList]) async {
    final events = eventsList ??
        ref.read(adminEventsProvider).valueOrNull ??
        const <AdminEvent>[];
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
    final cfg = ref.read(adminConfigProvider).value;
    final options = cfg?.eventTypes ?? kEventTypes;
    final chosen = await _pickFromSheet(
      title: context.t.eventsFilterByType,
      options: options,
      selected: _selectedEventType,
    );
    if (chosen == null) return;
    setState(() => _selectedEventType = chosen.isEmpty ? null : chosen);
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
    final hasCityFilter =
        _selectedEventCity != null && _selectedEventCity!.isNotEmpty;
    final hasTypeFilter =
        _selectedEventType != null && _selectedEventType!.isNotEmpty;

    return PopScope(
      canPop: !_isSearchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSearchOpen) {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _AnimatedSearchSection(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        animation: _searchAnim,
                        isSearchOpen: _isSearchOpen,
                        onOpenSearch: _openSearch,
                        onCloseSearch: _closeSearch,
                        hint: context.t.eventsSearchEvents,
                        cityActive: hasCityFilter,
                        onCityTap: _onEventCityTap,
                        cityTooltip:
                            _selectedEventCity ?? context.t.eventsFilterByCity,
                        typeActive: hasTypeFilter,
                        onTypeTap: _onEventTypeTap,
                        typeTooltip:
                            _selectedEventType ?? context.t.eventsFilterByType,
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
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: (hasCityFilter || hasTypeFilter)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (hasCityFilter)
                                  _ActiveFilterBadge(
                                    icon: Icons.location_on_rounded,
                                    label: _selectedEventCity!,
                                    onRemove: () => setState(
                                        () => _selectedEventCity = null),
                                  ),
                                if (hasCityFilter && hasTypeFilter)
                                  const SizedBox(width: 8),
                                if (hasTypeFilter)
                                  _ActiveFilterBadge(
                                    icon: Icons.tune_rounded,
                                    label: _selectedEventType!,
                                    onRemove: () => setState(
                                        () => _selectedEventType = null),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _EventsView(
                  query: _query,
                  selectedCity: _selectedEventCity,
                  selectedEventType: _selectedEventType,
                  layout: _eventsLayout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Animated Search & Filter Bar Section
// ─────────────────────────────────────────────────────────
class _AnimatedSearchSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Animation<double> animation;
  final bool isSearchOpen;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final String hint;
  final bool cityActive;
  final VoidCallback onCityTap;
  final String cityTooltip;
  final bool typeActive;
  final VoidCallback onTypeTap;
  final String typeTooltip;

  const _AnimatedSearchSection({
    required this.controller,
    required this.focusNode,
    required this.animation,
    required this.isSearchOpen,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.hint,
    required this.cityActive,
    required this.onCityTap,
    required this.cityTooltip,
    required this.typeActive,
    required this.onTypeTap,
    required this.typeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = animation.value;

            return SizedBox(
              height: 38,
              width: maxWidth,
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                clipBehavior: Clip.none,
                children: [
                  // 1. Filter and Search Icon Buttons (Visible when search is closed)
                  if (t < 0.99)
                    PositionedDirectional(
                      start: 0,
                      child: Opacity(
                        opacity: (1.0 - (t * 2.2)).clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: (1.0 - (t * 0.15)).clamp(0.85, 1.0),
                          alignment: AlignmentDirectional.centerStart,
                          child: IgnorePointer(
                            ignoring: t > 0.05,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _GlassIconButton(
                                  icon: Icons.search_rounded,
                                  onTap: onOpenSearch,
                                  tooltip: context.t.search,
                                ),
                                const SizedBox(width: 8),
                                _GlassIconButton(
                                  icon: Icons.location_on_rounded,
                                  active: cityActive,
                                  onTap: onCityTap,
                                  tooltip: cityTooltip,
                                ),
                                const SizedBox(width: 8),
                                _GlassIconButton(
                                  icon: Icons.tune_rounded,
                                  active: typeActive,
                                  onTap: onTypeTap,
                                  tooltip: typeTooltip,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 2. Expanding Search Input (Expands smoothly on tap)
                  if (t > 0.01)
                    PositionedDirectional(
                      start: 0,
                      child: SizedBox(
                        width: (38.0 + (maxWidth - 38.0) * t)
                            .clamp(38.0, maxWidth),
                        height: 38,
                        child: Opacity(
                          opacity: ((t - 0.05) / 0.95).clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: t < 0.8,
                            child: AppGlassCard(
                              height: 38,
                              radius: 19,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              surfaceAlpha: context.isDark ? 0.28 : 0.58,
                              borderAlpha: context.isDark ? 0.20 : 0.55,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: _kBrandPurple,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      textInputAction: TextInputAction.search,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        hintText: hint,
                                        hintStyle: TextStyle(
                                          fontSize: 13,
                                          color: context.textSecondary,
                                        ),
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: controller,
                                    builder: (_, value, __) {
                                      if (value.text.isNotEmpty) {
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: controller.clear,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: context.textSecondary,
                                            ),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                  const SizedBox(width: 2),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: onCloseSearch,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: _kBrandPurple
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: _kBrandPurple,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Glass Icon Button
// ─────────────────────────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final button = GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          active
              ? Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_kBrandPurple, _kBrandDeep],
                    ),
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: _kBrandPurple.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                )
              : AppGlassCard(
                  width: 38,
                  height: 38,
                  radius: 19,
                  surfaceAlpha: isDark ? 0.24 : 0.52,
                  borderAlpha: isDark ? 0.16 : 0.50,
                  child: Icon(icon, size: 18, color: _kBrandPurple),
                ),
          if (active)
            PositionedDirectional(
              top: -1,
              end: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF6EE7B7),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF101017) : Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

// ─────────────────────────────────────────────────────────
// Active Filter Badge (Shown when a filter is active)
// ─────────────────────────────────────────────────────────
class _ActiveFilterBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterBadge({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: _kBrandPurple.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kBrandPurple.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kBrandPurple),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : _kBrandDeep,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _kBrandPurple.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 12,
                color: _kBrandPurple,
              ),
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

  const _EventsView({
    required this.query,
    required this.selectedCity,
    required this.selectedEventType,
    required this.layout,
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

        if (filtered.isEmpty) {
          return _EmptyState(
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
          );
        }

        if (layout == _EventsLayout.map) {
          return _EventsMapView(events: filtered);
        }

        return RefreshIndicator(
          color: _kBrandPurple,
          onRefresh: () async {
            ref.invalidate(adminEventsProvider);
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _EventCard(
                      event: filtered[i],
                      recommended: (scored[filtered[i].id] ?? 0) > 0,
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                        const SizedBox(height: 4),
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
                        const SizedBox(height: 4),
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
        childAspectRatio: 0.66,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => const _ShimmerBlock(radius: 22),
    );
  }
}

class _ShimmerBlock extends StatefulWidget {
  final double radius;
  const _ShimmerBlock({this.radius = 20});

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
                      fillColor: context.surfaceSoft.withValues(alpha: 0.45),
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
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(
                          color: _kBrandPurple.withValues(alpha: 0.55),
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
                                    ? _kBrandPurple.withValues(alpha: 0.14)
                                    : context.surfaceSoft
                                        .withValues(alpha: 0.3),
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

class _EventsMapView extends ConsumerStatefulWidget {
  final List<AdminEvent> events;
  const _EventsMapView({required this.events});

  @override
  ConsumerState<_EventsMapView> createState() => _EventsMapViewState();
}

class _EventsMapViewState extends ConsumerState<_EventsMapView> {
  final Map<String, LatLng> _resolved = {};
  bool _resolving = false;

  final MapController _mapController = MapController();

  /// Whether we've already centered the map on the viewer's home location.
  /// The account profile loads asynchronously, so it may not be ready when the
  /// map first builds — once it arrives we recenter exactly once.
  bool _centeredOnHome = false;

  /// Centroid of the viewer's country, resolved from their saved `city` string
  /// (e.g. "Tbilisi, Georgia") when no precise GPS `location` exists. Lets the
  /// map still open on their country even if they denied GPS at signup.
  LatLng? _countryCentroid;
  bool _resolvingCentroid = false;
  String? _centroidSourceCity;

  /// Reads the viewer's precise home location from their account doc
  /// (`location: {lat,lng}`). Pass the already-loaded [profile] map so callers
  /// use the value watched in `build` (not a possibly-empty `ref.read`).
  /// Null when the account has no saved GPS location.
  LatLng? _homeLocationFrom(Map<String, dynamic>? profile) {
    final loc = profile?['location'];
    if (loc is Map) {
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
  }

  LatLng? _homeLocation() =>
      _homeLocationFrom(ref.read(currentUserDocProvider).valueOrNull);

  /// Where to center on the viewer: their precise GPS point if saved, else
  /// their country's centroid (resolved offline from the `city` string).
  LatLng? _viewerCenterFrom(Map<String, dynamic>? profile) =>
      _homeLocationFrom(profile) ?? _countryCentroid;

  /// Kicks off the offline country-centroid lookup from the saved `city`
  /// string when there's no GPS point. Runs once per distinct city value.
  void _ensureCountryCentroid(Map<String, dynamic>? profile) {
    if (_homeLocationFrom(profile) != null) return; // GPS point wins.
    final city = (profile?['city'] as String?)?.trim() ?? '';
    if (city.isEmpty || city == _centroidSourceCity || _resolvingCentroid) {
      return;
    }
    _resolvingCentroid = true;
    _centroidSourceCity = city;
    countryCentroidFromLocationString(city).then((centroid) {
      _resolvingCentroid = false;
      if (!mounted || centroid == null) return;
      setState(() => _countryCentroid = LatLng(centroid.lat, centroid.lng));
    });
  }

  @override
  void initState() {
    super.initState();
    _resolveAll();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
    // Default to the viewer's own country (their saved account location) so
    // the map opens on familiar ground rather than zoomed tight on a pin.
    final home = _homeLocation();
    if (home != null) return home;

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
    // Watch (not read) the profile so the map rebuilds when the account doc —
    // including the saved country location — finishes loading.
    final profile = ref.watch(currentUserDocProvider).valueOrNull;
    // If there's no GPS point, resolve the country centroid from the `city`
    // string so we can still open on the viewer's country.
    _ensureCountryCentroid(profile);
    final home = _viewerCenterFrom(profile);

    // Once a home center arrives (it may not be ready on first build — GPS or
    // the resolved country centroid land later), recenter on the viewer's
    // country exactly once. Deferred to after the frame so the controller is
    // attached before we move it.
    if (home != null && !_centeredOnHome) {
      _centeredOnHome = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(home, 5.5);
      });
    }

    // Group events by their resolved coordinate. Events in the same city are
    // geocoded to the SAME point (shared geocode cache) or share an admin pin,
    // so without spreading they stack exactly on top of each other and only the
    // topmost is visible. We fan co-located events out into a small ring around
    // the shared point so each event gets its own visible pin in a different
    // spot of the city.
    final byPoint = <String, List<AdminEvent>>{};
    for (final e in widget.events) {
      final p = _resolved[e.id];
      if (p == null) continue;
      // Round to ~11m so points that are effectively identical group together.
      final key = '${p.latitude.toStringAsFixed(4)},'
          '${p.longitude.toStringAsFixed(4)}';
      (byPoint[key] ??= <AdminEvent>[]).add(e);
    }

    final markers = <Marker>[];
    for (final group in byPoint.values) {
      // Single event at this point: place it exactly where it resolved.
      if (group.length == 1) {
        final e = group.first;
        final p = _resolved[e.id]!;
        markers.add(_buildEventMarker(e, p));
        continue;
      }
      // Multiple events share this point: spread them around a small ring so
      // they appear in different places of the same city. The ring radius
      // grows slightly with the count so larger clusters don't overlap.
      final base = _resolved[group.first.id]!;
      final radiusDeg = 0.006 + group.length * 0.0008; // ~0.7km + per event
      for (var i = 0; i < group.length; i++) {
        final angle = (2 * math.pi / group.length) * i;
        final latScale = math.cos(base.latitude * math.pi / 180).abs();
        final spread = LatLng(
          base.latitude + radiusDeg * math.sin(angle),
          base.longitude +
              (latScale == 0 ? 0 : radiusDeg * math.cos(angle) / latScale),
        );
        markers.add(_buildEventMarker(group[i], spread));
      }
    }

    final unresolved = widget.events.length - markers.length;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: home ?? _initialCenter(),
            // Open on the viewer's country by default (~5.5 = country level)
            // so they aren't dropped tight on a pin and forced to zoom out.
            // Without a saved home location, fall back to the events overview
            // (wide for many, regional for one).
            initialZoom: home != null ? 5.5 : (markers.length > 1 ? 4 : 9),
            minZoom: 2,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              // CARTO Voyager — a free, cleaner-looking basemap (softer colours,
              // clearer labels) than raw OSM. {r} pulls @2x retina tiles so the
              // map stays crisp on high-DPI phones. Free for reasonable use;
              // only requires keeping OSM + CARTO attribution below.
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: RetinaMode.isHighDensity(context),
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

  /// Builds a tappable event pin at [point]. [point] may be the event's exact
  /// resolved location, or a spread position when several events share a spot.
  Marker _buildEventMarker(AdminEvent e, LatLng point) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _showEventSheet(context, e, point),
        child: const _EventMapPin(),
      ),
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
