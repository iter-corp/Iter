import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import '../../providers/auth_providers.dart';
import '../../providers/admin_providers.dart';
import '../../theme/app_theme.dart';
import '../../providers/post_providers.dart';
import '../../services/post_service.dart';
import '../model/post_model.dart';
import '../widgets/header.dart';
import '../widgets/post_card.dart';
import '../widgets/story_section.dart';

enum _HomeMode { feed, travel }

enum _LocationStatus {
  ok,
  alreadyResolving,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

class _PlaceSuggestion {
  final String name;
  final String city;
  final double? lat;
  final double? lng;
  final bool useCurrentLocation;

  const _PlaceSuggestion({
    required this.name,
    required this.city,
    this.lat,
    this.lng,
    this.useCurrentLocation = false,
  });
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const HomeBody(),
    );
  }
}

class HomeBody extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const HomeBody({super.key, this.scrollController});

  @override
  ConsumerState<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<HomeBody> {
  _HomeMode _mode = _HomeMode.feed;
  _PlaceSuggestion? _selectedPlace;
  final List<_PlaceSuggestion> _recentPlaces = [];
  double? _viewerLat;
  double? _viewerLng;
  String _viewerCity = 'Location unavailable';
  bool _resolvingLocation = false;

  String _defaultCityQuery() {
    final raw = _viewerCity.trim();
    if (raw.isEmpty) return '';
    if (raw.toLowerCase() == 'location unavailable') return '';
    return raw.split(',').first.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewerLocation();
    });
  }

  Future<void> _refresh(WidgetRef ref) async {
    if (_mode == _HomeMode.travel) {
      if (mounted) {
        setState(() {
          _selectedPlace = null;
        });
      }
      final query = TravelFeedQuery(
        placeQuery: _defaultCityQuery(),
        lat: _viewerLat,
        lng: _viewerLng,
        limit: 80,
      );
      ref.invalidate(travelFeedProvider(query));
      await ref.read(travelFeedProvider(query).future);
      return;
    }

    ref.invalidate(feedProvider);
    try {
      await ref.read(feedProvider.future);
    } catch (_) {
      // Swallow — the error state already renders in the list.
    }
  }

  Future<_LocationStatus> _ensureViewerLocation() async {
    if (_resolvingLocation) return _LocationStatus.alreadyResolving;
    if (_viewerLat != null && _viewerLng != null) {
      return _LocationStatus.ok;
    }

    _resolvingLocation = true;
    var status = _LocationStatus.unknown;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        status = _LocationStatus.serviceDisabled;
        return status;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        status = _LocationStatus.permissionDeniedForever;
        return status;
      }
      if (perm == LocationPermission.denied) {
        status = _LocationStatus.permissionDenied;
        return status;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      String city = _viewerCity;
      try {
        final places =
            await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          final local = (p.locality ?? p.subAdministrativeArea ?? '').trim();
          final country = (p.isoCountryCode ?? '').trim();
          if (local.isNotEmpty) {
            city = country.isEmpty ? local : '$local, $country';
          }
        }
      } catch (_) {}

      if (!mounted) return _LocationStatus.ok;
      setState(() {
        _viewerLat = pos.latitude;
        _viewerLng = pos.longitude;
        _viewerCity = city;
      });
      status = _LocationStatus.ok;
      return status;
    } catch (_) {
      status = _LocationStatus.unknown;
      return status;
    } finally {
      if (!mounted) {
        _resolvingLocation = false;
      } else {
        // Always try the saved profile location as a silent fallback so the
        // travel feed has *something* to render even when GPS is unavailable.
        if (_viewerLat == null || _viewerLng == null) {
          final profile = ref.read(currentUserDocProvider).valueOrNull;
          final profileLoc = profile?['location'];
          if (profileLoc is Map) {
            final lat = (profileLoc['lat'] as num?)?.toDouble();
            final lng = (profileLoc['lng'] as num?)?.toDouble();
            if (lat != null && lng != null && mounted) {
              setState(() {
                _viewerLat = lat;
                _viewerLng = lng;
                final city = (profile?['city'] as String?)?.trim();
                if (city != null && city.isNotEmpty) {
                  _viewerCity = city;
                }
              });
            }
          }
        }
      }
      _resolvingLocation = false;
    }
  }

  /// Show a user-facing message when location couldn't be resolved during a
  /// user-initiated action (e.g. switching to Travel Mode). Includes an
  /// action button that opens the relevant system settings page.
  void _showLocationStatusMessage(_LocationStatus status) {
    if (!mounted) return;
    String message;
    String? actionLabel;
    Future<void> Function()? onAction;

    switch (status) {
      case _LocationStatus.serviceDisabled:
        message = 'Location services are turned off. '
            'Turn them on so Travel Mode can show nearby posts.';
        actionLabel = 'Open settings';
        onAction = Geolocator.openLocationSettings;
        break;
      case _LocationStatus.permissionDenied:
        message = 'Location permission was denied. '
            'Travel Mode works best with your location.';
        actionLabel = 'Try again';
        onAction = () async {
          await _ensureViewerLocation();
        };
        break;
      case _LocationStatus.permissionDeniedForever:
        message = 'Location permission is blocked. '
            'Enable it in app settings to use Travel Mode.';
        actionLabel = 'App settings';
        onAction = Geolocator.openAppSettings;
        break;
      case _LocationStatus.unknown:
        message = "Couldn't get your location. "
            'You can still search for a place manually.';
        break;
      case _LocationStatus.ok:
      case _LocationStatus.alreadyResolving:
        return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: () {
                  onAction?.call();
                },
              ),
      ),
    );
  }

  Future<void> _openPlaceSearch() async {
    final selected = await Navigator.push<_PlaceSuggestion>(
      context,
      MaterialPageRoute(
        builder: (_) => _PlaceSearchScreen(
          currentPlace: _selectedPlace,
          recents: _recentPlaces,
          currentLat: _viewerLat,
          currentLng: _viewerLng,
          currentLocationLabel: _viewerCity,
        ),
      ),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedPlace = selected;
      _recentPlaces.removeWhere((p) => p.name == selected.name);
      _recentPlaces.insert(0, selected);
      if (_recentPlaces.length > 5) {
        _recentPlaces.removeRange(5, _recentPlaces.length);
      }
    });
  }

  TravelFeedQuery _buildTravelQuery() {
    // "All places" (no chip selected) MUST send an empty placeQuery so the
    // service skips its name-match filter and returns travel posts from
    // every location. Falling back to the user's city here would silently
    // turn "All places" into "Nearby" — which was the previous bug.
    String placeQuery;
    if (_selectedPlace == null) {
      placeQuery = '';
    } else if (_selectedPlace!.useCurrentLocation) {
      placeQuery = _defaultCityQuery();
    } else {
      placeQuery = _selectedPlace!.city.isEmpty
          ? _selectedPlace!.name
          : '${_selectedPlace!.name} ${_selectedPlace!.city}';
    }

    return TravelFeedQuery(
      placeQuery: placeQuery,
      lat: _viewerLat,
      lng: _viewerLng,
      limit: 80,
    );
  }

  Future<void> _switchMode(_HomeMode mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);

    if (mode == _HomeMode.travel) {
      final status = await _ensureViewerLocation();
      if (!mounted) return;
      _showLocationStatusMessage(status);
      final query = _buildTravelQuery();
      ref.invalidate(travelFeedProvider(query));
      try {
        await ref.read(travelFeedProvider(query).future);
      } catch (_) {
        // Let the UI render the provider error state.
      }
      return;
    }

    ref.invalidate(feedProvider);
    try {
      await ref.read(feedProvider.future);
    } catch (_) {
      // Let the UI render the provider error state.
    }
  }

  List<Widget> _topContent({
    required String announcement,
    required bool maintenance,
    required bool showStories,
  }) {
    return [
      if (announcement.isNotEmpty)
        _AnnouncementBanner(announcement: announcement),
      if (maintenance) const _MaintenanceBanner(),
      if (showStories) const StoriesList(),
      const SizedBox(height: 8),
      _HomeModeToggle(
        mode: _mode,
        onChanged: _switchMode,
      ),
      if (_mode == _HomeMode.travel) ...[
        _TravelLocationRow(
          selectedPlace: _selectedPlace,
          onSearchPressed: _openPlaceSearch,
          viewerCity: _viewerCity,
        ),
        _TravelQuickFilters(
          selectedPlace: _selectedPlace,
          recents: _recentPlaces,
          viewerCity: _viewerCity,
          onSelectAll: () {
            setState(() => _selectedPlace = null);
          },
          onSelectNearby: _viewerLat == null || _viewerLng == null
              ? null
              : () {
                  setState(() {
                    _selectedPlace = _PlaceSuggestion(
                      name: _viewerCity.isNotEmpty ? _viewerCity : 'Nearby',
                      city: '',
                      lat: _viewerLat,
                      lng: _viewerLng,
                      useCurrentLocation: true,
                    );
                  });
                },
          onSelectRecent: (place) => setState(() => _selectedPlace = place),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserDocProvider).valueOrNull;
    if ((_viewerLat == null || _viewerLng == null) &&
        !_resolvingLocation &&
        profile != null) {
      final profileLoc = profile['location'];
      if (profileLoc is Map) {
        final lat = (profileLoc['lat'] as num?)?.toDouble();
        final lng = (profileLoc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _viewerLat = lat;
              _viewerLng = lng;
              final city = (profile['city'] as String?)?.trim();
              if (city != null && city.isNotEmpty) {
                _viewerCity = city;
              }
            });
          });
        }
      }
    }

    final travelQuery = _buildTravelQuery();

    final postsAsync = _mode == _HomeMode.travel
        ? ref.watch(travelFeedProvider(travelQuery))
        : ref.watch(feedProvider);

    // Tolerate the adminConfig doc being missing or the rules not yet
    // deployed — both should fail silently (no banner shown).
    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final announcement = cfg?.announcement ?? '';
    final maintenance = cfg?.maintenanceMode ?? false;
    final showStories = cfg?.storiesEnabled ?? true;

    return SafeArea(
      child: Column(
        children: [
          const HeaderWidget(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: postsAsync.when(
                skipLoadingOnReload: true,
                skipLoadingOnRefresh: true,
                loading: () => ListView(
                  controller: widget.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    ..._topContent(
                      announcement: announcement,
                      maintenance: maintenance,
                      showStories: showStories,
                    ),
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ),
                error: (e, _) => ListView(
                  controller: widget.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    ..._topContent(
                      announcement: announcement,
                      maintenance: maintenance,
                      showStories: showStories,
                    ),
                    const SizedBox(height: 24),
                    Center(child: Text('Error: $e')),
                  ],
                ),
                data: (posts) {
                  if (posts.isEmpty) {
                    return ListView(
                      controller: widget.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        ..._topContent(
                          announcement: announcement,
                          maintenance: maintenance,
                          showStories: showStories,
                        ),
                        const SizedBox(height: 24),
                        const Center(
                          child: Text('No posts yet. Create the first one!'),
                        ),
                      ],
                    );
                  }
                  return CustomScrollView(
                    controller: widget.scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: _topContent(
                            announcement: announcement,
                            maintenance: maintenance,
                            showStories: showStories,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        sliver: SliverList.builder(
                          itemCount: posts.length,
                          itemBuilder: (context, index) {
                            final p = posts[index];
                            final placeLabel = _travelPlaceLabel(p);
                            final hasPlace = placeLabel.isNotEmpty;
                            final viewerLocOff = _mode == _HomeMode.travel &&
                                (_viewerLat == null || _viewerLng == null);
                            return PostCard(
                              post: p,
                              travelMode: _mode == _HomeMode.travel,
                              travelPlace: _mode == _HomeMode.travel && hasPlace
                                  ? placeLabel
                                  : null,
                              travelDistance: _mode == _HomeMode.travel
                                  ? (p.travelDistanceLabel ?? '')
                                  : null,
                              viewerLocationOff: viewerLocOff,
                              onTurnOnLocationTap: viewerLocOff
                                  ? () async {
                                      final status =
                                          await _ensureViewerLocation();
                                      _showLocationStatusMessage(status);
                                      if (status == _LocationStatus.ok) {
                                        ref.invalidate(travelFeedProvider(
                                            _buildTravelQuery()));
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _travelPlaceLabel(Post post) {
    final name = (post.postPlaceName ?? '').trim();
    final city = (post.postPlaceCity ?? '').trim();
    if (name.isEmpty) return city;
    if (city.isEmpty) return name;
    return '$name, $city';
  }
}

class _HomeModeToggle extends StatelessWidget {
  final _HomeMode mode;
  final ValueChanged<_HomeMode> onChanged;

  const _HomeModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selectedColor = context.cardBg;
    final unselectedColor = context.inputFill;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: unselectedColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ModePillButton(
                label: 'Feed',
                selected: mode == _HomeMode.feed,
                selectedColor: selectedColor,
                onTap: () => onChanged(_HomeMode.feed),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ModePillButton(
                label: 'Travel Mode',
                icon: Icons.flight,
                selected: mode == _HomeMode.travel,
                selectedColor: selectedColor,
                onTap: () => onChanged(_HomeMode.travel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _ModePillButton({
    required this.label,
    this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: context.borderColor)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: context.textPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelLocationRow extends StatelessWidget {
  final _PlaceSuggestion? selectedPlace;
  final VoidCallback onSearchPressed;
  final String viewerCity;

  const _TravelLocationRow({
    required this.selectedPlace,
    required this.onSearchPressed,
    required this.viewerCity,
  });

  @override
  Widget build(BuildContext context) {
    final placeText = selectedPlace == null
        ? viewerCity
        : (selectedPlace!.city.isEmpty
            ? selectedPlace!.name
            : '${selectedPlace!.name} · ${selectedPlace!.city}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Icon(Icons.location_on, size: 20, color: context.textPrimary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              placeText,
              style: TextStyle(
                fontSize: 28 / 2,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onSearchPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: context.isDark ? 0 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'Search place',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceSearchScreen extends ConsumerStatefulWidget {
  final _PlaceSuggestion? currentPlace;
  final List<_PlaceSuggestion> recents;
  final double? currentLat;
  final double? currentLng;
  final String currentLocationLabel;

  const _PlaceSearchScreen({
    required this.currentPlace,
    required this.recents,
    required this.currentLat,
    required this.currentLng,
    required this.currentLocationLabel,
  });

  @override
  ConsumerState<_PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<_PlaceSearchScreen> {
  late final TextEditingController _searchCtrl;
  Timer? _debounce;
  List<TravelPlaceResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.currentPlace?.name ?? '');
    _loadPlaces();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(postServiceProvider).searchTravelPlaces(
            query: _searchCtrl.text,
            limit: 30,
          );
      if (!mounted) return;
      setState(() {
        _results = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load places right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _loadPlaces);
  }

  Widget _searchField(BuildContext context) {
    final query = _searchCtrl.text.trim();
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.isDark
                ? Colors.black.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF393943)
              : const Color(0xFFDCC8E6),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.purpleSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 20,
              color: Color(0xFF7E3BE8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search place in travel posts...',
                hintStyle: TextStyle(color: context.textSecondary),
                border: InputBorder.none,
                isDense: true,
                filled: false,
              ),
            ),
          ),
          if (query.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchCtrl.clear();
                _loadPlaces();
              },
              icon: const Icon(Icons.close_rounded),
              iconSize: 18,
              color: context.textSecondary,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _PlaceSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPlace?.name != widget.currentPlace?.name) {
      _searchCtrl.text = widget.currentPlace?.name ?? '';
      _loadPlaces();
    }
  }

  _PlaceSuggestion _placeFromResult(TravelPlaceResult p) {
    return _PlaceSuggestion(
      name: p.name,
      city: p.city,
      lat: p.lat,
      lng: p.lng,
    );
  }

  Widget _currentLocationCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(
          context,
          _PlaceSuggestion(
            name: 'Use my current location',
            city: widget.currentLocationLabel,
            lat: widget.currentLat,
            lng: widget.currentLng,
            useCurrentLocation: true,
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.purpleSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.my_location_rounded,
                    size: 18, color: Color(0xFF7E3BE8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use my current location',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.currentLocationLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    final hasQuery = query.isNotEmpty;

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Text(
                    'Search Place',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _searchField(context),
              const SizedBox(height: 12),
              _currentLocationCard(context),
              const SizedBox(height: 14),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: TextStyle(color: context.textSecondary),
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  'No places found in travel posts.',
                                  style:
                                      TextStyle(color: context.textSecondary),
                                ),
                              )
                            : ListView(
                                children: [
                                  if (!hasQuery &&
                                      widget.recents.isNotEmpty) ...[
                                    Text(
                                      'Recent',
                                      style: TextStyle(
                                        color: context.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: widget.recents.map((p) {
                                        return ActionChip(
                                          onPressed: () =>
                                              Navigator.pop(context, p),
                                          label: Text(p.name),
                                          backgroundColor: context.cardBg,
                                          side: BorderSide(
                                              color: context.borderColor),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  Text(
                                    hasQuery
                                        ? 'Results'
                                        : 'Popular from travel posts',
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ..._results.map((p) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: context.cardBg,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: context.borderColor),
                                      ),
                                      child: ListTile(
                                        leading: Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: context.purpleSoft,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.location_on_rounded,
                                            size: 17,
                                            color: Color(0xFF7E3BE8),
                                          ),
                                        ),
                                        title: Text(
                                          p.name,
                                          style: TextStyle(
                                            color: context.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          p.city.isEmpty
                                              ? 'Unknown city'
                                              : p.city,
                                          style: TextStyle(
                                              color: context.textSecondary),
                                        ),
                                        onTap: () => Navigator.pop(
                                            context, _placeFromResult(p)),
                                      ),
                                    );
                                  }),
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
        color:
            context.isDark ? const Color(0xFF2D1A30) : const Color(0xFFFFF1F8),
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
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimary,
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
        color: context.isDark ? const Color(0xFF3D2E1A) : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Maintenance mode — some features may be unavailable.',
              style: TextStyle(fontSize: 13, color: context.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal chip strip shown above the travel feed. One-tap filters for
/// "All places", "Nearby" (uses GPS), and the user's recently-viewed
/// places. Tapping a chip swaps the active travel place and the feed
/// re-queries automatically.
class _TravelQuickFilters extends StatelessWidget {
  final _PlaceSuggestion? selectedPlace;
  final List<_PlaceSuggestion> recents;
  final String viewerCity;
  final VoidCallback onSelectAll;
  final VoidCallback? onSelectNearby;
  final void Function(_PlaceSuggestion) onSelectRecent;

  const _TravelQuickFilters({
    required this.selectedPlace,
    required this.recents,
    required this.viewerCity,
    required this.onSelectAll,
    required this.onSelectNearby,
    required this.onSelectRecent,
  });

  @override
  Widget build(BuildContext context) {
    final activeName = selectedPlace?.name;
    final isAll = selectedPlace == null;
    final isNearby = selectedPlace?.useCurrentLocation == true;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _TravelFilterChip(
            label: 'All places',
            icon: Icons.public,
            selected: isAll,
            onTap: onSelectAll,
          ),
          const SizedBox(width: 6),
          _TravelFilterChip(
            label: viewerCity.isNotEmpty ? 'Nearby · $viewerCity' : 'Nearby',
            icon: Icons.my_location,
            selected: isNearby,
            onTap: onSelectNearby,
          ),
          for (final place in recents) ...[
            const SizedBox(width: 6),
            _TravelFilterChip(
              label: place.name,
              icon: Icons.place_outlined,
              selected: !isAll && !isNearby && activeName == place.name,
              onTap: () => onSelectRecent(place),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill-shaped filter chip used by [_TravelQuickFilters]. Matches the
/// app's purple accent for the active state and uses muted surface for
/// the inactive state. [onTap] of null disables the chip (e.g. Nearby
/// when no location is available yet).
class _TravelFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  const _TravelFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    const purple = Color(0xFFB05ECC);
    final bg = selected
        ? purple
        : (disabled
            ? context.inputFill.withValues(alpha: 0.5)
            : context.inputFill);
    final fg = selected
        ? Colors.white
        : (disabled ? context.textMuted : context.textPrimary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? purple : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
