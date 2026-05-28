import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/admin_providers.dart';
import '../../providers/comment_providers.dart';
import '../../providers/notification_providers.dart';
import '../../theme/app_theme.dart';
import '../../providers/post_providers.dart';
import '../../services/post_service.dart';
import '../../utils/media_cache.dart';
import '../model/post_model.dart';
import 'create_post_screen.dart';
import 'notification_screen.dart';
import 'post_detail_screen.dart';
import 'qa_thread_screen.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/post_card.dart';
import '../widgets/story_section.dart';

enum _HomeMode { feed, travel, qa }

enum _LocationStatus {
  ok,
  alreadyResolving,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

const _kTravelFilterPurple = Color(0xFFB05ECC);
const _kTravelAllOption = '__all_places__';
const _kTravelCurrentOption = '__current_location__';
const _kHomeModePrefsKey = 'home.selected_mode';

class _PlaceSuggestion {
  final String name;
  final String city;
  final double? lat;
  final double? lng;
  final bool useCurrentLocation;
  final String? queryText;

  const _PlaceSuggestion({
    required this.name,
    required this.city,
    this.lat,
    this.lng,
    this.useCurrentLocation = false,
    this.queryText,
  });
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Transparent so the per-tab background painted by MainScreen
    // shows through — otherwise a white Scaffold here peeked out as
    // strips above/below the SafeArea content.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: HomeBody(),
    );
  }
}

class HomeBody extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const HomeBody({super.key, this.scrollController});

  @override
  ConsumerState<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<HomeBody>
    with WidgetsBindingObserver {
  _HomeMode _mode = _HomeMode.feed;
  _PlaceSuggestion? _selectedPlace;
  final List<_PlaceSuggestion> _recentPlaces = [];

  // A single global search shared by all three tabs. Whichever tab the
  // user opens it from, the results combine matching Feed posts, Travel
  // posts and Discuss questions into one list.
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Discuss search also matches answers. Because answers (comments)
  // aren't loaded with the QA posts, the answer lookup is async — its
  // result (the set of QA post ids with a matching answer) is cached
  // here, recomputed after a short debounce as the user types.
  Set<String> _qaAnswerMatches = <String>{};
  String _qaAnswerMatchesQuery = '';
  Timer? _qaAnswerSearchDebounce;

  // When the search field is focused, the header + stories collapse and
  // the mode tabs pin to the top so the results get maximum space.
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  double? _viewerLat;
  double? _viewerLng;
  String _viewerCity = '';
  bool _resolvingLocation = false;

  /// Localized label for the resolved city. Empty internally means
  /// "not resolved yet"; UI surfaces a translated "Location unavailable"
  /// fallback so this never leaks raw English to non-English users.
  String _viewerCityLabel(BuildContext context) =>
      _viewerCity.isEmpty ? context.t.homeLocationUnavailable : _viewerCity;

  String _defaultCityQuery() {
    final raw = _viewerCity.trim();
    if (raw.isEmpty) return '';
    return raw.split(',').first.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSavedMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewerLocation();
    });
    _searchFocus.addListener(_onSearchFocusChange);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns from the system location settings, re-check
    // — if they enabled location the red travel banner auto-hides.
    if (state == AppLifecycleState.resumed &&
        (_viewerLat == null || _viewerLng == null)) {
      _ensureViewerLocation().then((status) {
        if (status == _LocationStatus.ok && mounted) {
          ref.invalidate(travelFeedProvider(_buildTravelQuery()));
        }
      });
    }
  }

  void _onSearchFocusChange() {
    final focused = _searchFocus.hasFocus;
    if (focused != _searchFocused && mounted) {
      setState(() => _searchFocused = focused);
    }
  }

  _HomeMode? _modeFromPrefs(String? value) {
    return switch (value) {
      'feed' => _HomeMode.feed,
      'travel' => _HomeMode.travel,
      'qa' => _HomeMode.qa,
      _ => null,
    };
  }

  Future<void> _loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = _modeFromPrefs(prefs.getString(_kHomeModePrefsKey));
      if (!mounted || savedMode == null || savedMode == _mode) return;
      setState(() => _mode = savedMode);

      if (savedMode == _HomeMode.travel) {
        await _ensureViewerLocation();
        if (!mounted) return;
        ref.invalidate(travelFeedProvider(_buildTravelQuery()));
      } else if (savedMode == _HomeMode.qa) {
        ref.invalidate(qaFeedProvider);
      }
    } catch (_) {
      // Keep the default feed mode if local preferences are unavailable.
    }
  }

  Future<void> _saveMode(_HomeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHomeModePrefsKey, mode.name);
    } catch (_) {
      // Mode persistence should never block using the main page.
    }
  }

  /// The single global search query, shared by all three tabs.
  String get _currentSearch => _searchQuery;

  /// True once the user has run a search and results are showing
  /// (a query exists and the keyboard is dismissed). In this state
  /// the tabs hide and the search bar shows the query as a chip.
  bool get _showingSearchResults =>
      !_searchFocused && _currentSearch.isNotEmpty;

  /// True whenever search is in play — either the keyboard is open
  /// (typing) or results are showing. Used to pin the search row above
  /// the scrolling list so it never scrolls away.
  bool get _searchActive => _searchFocused || _showingSearchResults;

  /// Clears the global search query and field.
  void _clearCurrentSearch() {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _qaAnswerMatches = <String>{};
      _qaAnswerMatchesQuery = '';
    });
    _qaAnswerSearchDebounce?.cancel();
  }

  /// Debounced answer search for Discuss results. Question-text
  /// matching is instant (done in the build); this fills in the extra
  /// matches whose ANSWER text contains the query.
  void _scheduleQaAnswerSearch() {
    _qaAnswerSearchDebounce?.cancel();
    final query = _searchQuery;
    if (query.isEmpty) {
      if (_qaAnswerMatches.isNotEmpty) {
        setState(() {
          _qaAnswerMatches = <String>{};
          _qaAnswerMatchesQuery = '';
        });
      }
      return;
    }
    _qaAnswerSearchDebounce =
        Timer(const Duration(milliseconds: 350), () async {
      final posts = ref.read(qaFeedProvider).valueOrNull ?? const <Post>[];
      final ids = posts.map((p) => p.id);
      try {
        final matches = await ref
            .read(postServiceProvider)
            .qaPostsWithMatchingAnswer(ids, query);
        if (!mounted || _searchQuery != query) return;
        setState(() {
          _qaAnswerMatches = matches;
          _qaAnswerMatchesQuery = query;
        });
      } catch (_) {
        // Answer search is best-effort; question-text search still works.
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qaAnswerSearchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh(WidgetRef ref) async {
    if (_mode == _HomeMode.travel) {
      final query = _buildTravelQuery();
      ref.invalidate(travelFeedProvider(query));
      await ref.read(travelFeedProvider(query).future);
      return;
    }

    if (_mode == _HomeMode.qa) {
      ref.invalidate(qaFeedProvider);
      try {
        await ref.read(qaFeedProvider.future);
      } catch (_) {
        // Swallow — the error state already renders in the list.
      }
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

  /// Handler for the red travel banner's "Enable" button. It first
  /// tries to resolve the location directly (this triggers the iOS/
  /// Android permission prompt). If that fails because the OS-level
  /// location *service* is off, it opens the system location settings
  /// — there is no in-app way to flip that switch. No snackbar is
  /// shown; the red banner itself is the only message, and it hides
  /// automatically once a location is obtained.
  Future<void> _enableLocationFromBanner() async {
    final status = await _ensureViewerLocation();

    if (status == _LocationStatus.ok) {
      // Location resolved — refresh the feed; the banner disappears
      // because _viewerLat/_viewerLng are now set.
      ref.invalidate(travelFeedProvider(_buildTravelQuery()));
      return;
    }

    // Couldn't get location — send the user straight to the right
    // system settings page so they can actually turn it on.
    switch (status) {
      case _LocationStatus.serviceDisabled:
        await Geolocator.openLocationSettings();
        break;
      case _LocationStatus.permissionDeniedForever:
        await Geolocator.openAppSettings();
        break;
      case _LocationStatus.permissionDenied:
      case _LocationStatus.unknown:
      case _LocationStatus.alreadyResolving:
      case _LocationStatus.ok:
        // permissionDenied already re-prompted inside
        // _ensureViewerLocation; nothing more to open.
        break;
    }
  }

  // Travel place-picker. No longer wired to the search icon (search is
  // now a global text search across all tabs) but kept for the Travel
  // quick-filter "more places" affordance.
  // ignore: unused_element
  Future<void> _openPlaceSearch() async {
    final data = await ref.read(postServiceProvider).searchTravelPlaces(
          query: '',
          limit: 200,
        );
    if (!mounted) return;

    final options = data
        .map((p) => p.city.trim().isEmpty ? p.name.trim() : p.city.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final selected = _selectedPlace == null
        ? _kTravelAllOption
        : _selectedPlace!.useCurrentLocation
            ? _kTravelCurrentOption
            : ((_selectedPlace!.queryText ?? '').trim().isNotEmpty
                ? _selectedPlace!.queryText!.trim()
                : _selectedPlace!.name.trim());

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TravelFilterSheet(
        title: context.t.homeFilterByCityCountry,
        options: options,
        selected: selected,
        currentLocationLabel: _viewerCityLabel(context),
        showCurrentLocation: _viewerLat != null && _viewerLng != null,
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() {
      if (chosen == _kTravelAllOption || chosen.isEmpty) {
        _selectedPlace = null;
        return;
      }
      if (chosen == _kTravelCurrentOption) {
        _selectedPlace = _PlaceSuggestion(
          name: _viewerCity.isEmpty
              ? context.t.homeCurrentLocation
              : _viewerCity,
          city: '',
          lat: _viewerLat,
          lng: _viewerLng,
          useCurrentLocation: true,
        );
        return;
      }
      _selectedPlace = _PlaceSuggestion(
        name: chosen,
        city: '',
        queryText: chosen,
      );
    });
  }

  TravelFeedQuery _buildTravelQuery() {
    String placeQuery;
    if (_selectedPlace == null) {
      placeQuery = '';
    } else if (_selectedPlace!.useCurrentLocation) {
      placeQuery = _defaultCityQuery();
    } else if ((_selectedPlace!.queryText ?? '').trim().isNotEmpty) {
      placeQuery = _selectedPlace!.queryText!.trim();
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
    unawaited(_saveMode(mode));

    if (mode == _HomeMode.travel) {
      // Resolve location silently — if it's off, the red in-feed
      // banner is the only message shown (no snackbar).
      await _ensureViewerLocation();
      if (!mounted) return;
      final query = _buildTravelQuery();
      ref.invalidate(travelFeedProvider(query));
      try {
        await ref.read(travelFeedProvider(query).future);
      } catch (_) {}
      return;
    }

    if (mode == _HomeMode.qa) {
      ref.invalidate(qaFeedProvider);
      try {
        await ref.read(qaFeedProvider.future);
      } catch (_) {}
      return;
    }

    ref.invalidate(feedProvider);
    try {
      await ref.read(feedProvider.future);
    } catch (_) {}
  }

  /// Top content for the scrolling list. Returns empty while a search
  /// field is focused, because [_topContent] is then rendered pinned
  /// above the list instead (see [build]).
  List<Widget> _scrollTopContent({
    required String announcement,
    required bool maintenance,
    required bool showStories,
  }) {
    if (_searchActive) return const <Widget>[];
    return _topContent(
      announcement: announcement,
      maintenance: maintenance,
      showStories: showStories,
    );
  }

  List<Widget> _topContent({
    required String announcement,
    required bool maintenance,
    required bool showStories,
  }) {
    // While search is active (typing or showing results), banners +
    // stories collapse so the results get the full screen. The tabs
    // stay visible while typing; once results show they are replaced
    // by the "Itr" title.
    final collapsed = _searchActive;

    return [
      if (!collapsed) ...[
        if (announcement.isNotEmpty)
          _AnnouncementBanner(announcement: announcement),
        if (maintenance) const _MaintenanceBanner(),
      ],
      SizedBox(height: collapsed ? 4 : 8),
      // App-bar row — "Itr" title + mode dropdown + notification bell.
      _HomeModeToggle(
        mode: _mode,
        onChanged: _switchMode,
      ),
      // Stories — directly under the tabs, identical on every tab.
      // Hidden while search is active.
      if (showStories && !collapsed)
        const StoriesList(),
      // Search + Post row — one global search shared by every tab.
      _SearchPostRow(
        searching: _searchFocused,
        query: _currentSearch,
        hintText: context.t.homeSearchPosts,
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: (value) {
          setState(() => _searchQuery = value.trim());
          _scheduleQaAnswerSearch();
        },
        onClear: _clearCurrentSearch,
        onSearchTap: () {
          // Flip to the expanded layout; the inline TextField then
          // appears with autofocus:true and grabs the keyboard.
          setState(() => _searchFocused = true);
        },
        onPost: () {
          // In Discuss, "Post" opens the ask-a-question sheet;
          // elsewhere it opens the create-post screen.
          if (_mode == _HomeMode.qa) {
            _showAskSheet(context);
          } else {
            _openCreatePost(context);
          }
        },
        onDismissSearch: () {
          FocusScope.of(context).unfocus();
        },
      ),
      if (_mode == _HomeMode.travel) ...[
        // The old inline location row was replaced by the search icon
        // in _SearchPostRow (which opens the travel search page).
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
                      name: _viewerCity.isNotEmpty
                          ? _viewerCity
                          : context.t.homeNearby,
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

  /// Builds the combined, all-tabs search result list. Merges matching
  /// Feed posts, Travel posts and Discuss questions into one scroll
  /// view, each rendered with its own card type. Returns null while the
  /// underlying providers are still loading their first data.
  Widget? _buildSearchResults({
    required AsyncValue<List<Post>>? feedAsync,
    required AsyncValue<List<Post>>? travelAsync,
    required AsyncValue<List<Post>>? qaAsync,
    required List<Widget> topContent,
  }) {
    final feedPosts = feedAsync?.valueOrNull;
    final travelPosts = travelAsync?.valueOrNull;
    final qaPosts = qaAsync?.valueOrNull;

    // Wait until every provider has produced at least one value so the
    // merged list isn't half-empty on first paint.
    if (feedPosts == null || travelPosts == null || qaPosts == null) {
      return null;
    }

    final answerMatches =
        _qaAnswerMatchesQuery == _searchQuery && _searchQuery.isNotEmpty
            ? _qaAnswerMatches
            : const <String>{};

    // De-dupe across tabs by post id (a post may surface in both Feed
    // and Travel). Feed wins first, then Travel, then Discuss.
    final seen = <String>{};
    final hits = <_SearchHit>[];
    for (final p in _filterFeedPosts(feedPosts, _searchQuery)) {
      if (seen.add(p.id)) hits.add(_SearchHit(p, _HomeMode.feed));
    }
    for (final p in _filterFeedPosts(travelPosts, _searchQuery)) {
      if (seen.add(p.id)) hits.add(_SearchHit(p, _HomeMode.travel));
    }
    for (final p in _filterQaPosts(qaPosts, _searchQuery, answerMatches)) {
      if (seen.add(p.id)) hits.add(_SearchHit(p, _HomeMode.qa));
    }

    if (hits.isEmpty) {
      return ListView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          ...topContent,
          const SizedBox(height: 24),
          Center(child: Text(context.t.homeNoMatchingPosts)),
        ],
      );
    }

    return CustomScrollView(
      controller: widget.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: Column(children: topContent)),
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          sliver: SliverList.builder(
            itemCount: hits.length,
            itemBuilder: (context, index) {
              final hit = hits[index];
              final p = hit.post;
              if (hit.origin == _HomeMode.qa) {
                return _QaThreadCard(key: ValueKey('qa_${p.id}'), post: p);
              }
              final isTravel = hit.origin == _HomeMode.travel;
              final placeLabel = isTravel ? _travelPlaceLabel(p) : '';
              return PostCard(
                key: ValueKey('${isTravel ? 'travel' : 'feed'}_${p.id}'),
                post: p,
                travelMode: isTravel,
                travelPlace:
                    isTravel && placeLabel.isNotEmpty ? placeLabel : null,
                travelDistance:
                    isTravel ? (p.travelDistanceLabel ?? '') : null,
                viewerLocationOff: false,
              );
            },
          ),
        ),
      ],
    );
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

    // The global search merges all three tabs, so while it is active we
    // need every provider. When it is idle only the current tab's
    // provider matters.
    final searching = _searchActive && _searchQuery.isNotEmpty;

    final postsAsync = _mode == _HomeMode.travel
        ? ref.watch(travelFeedProvider(travelQuery))
        : _mode == _HomeMode.qa
            ? ref.watch(qaFeedProvider)
            : ref.watch(feedProvider);

    // Extra providers consulted only while a global search is running.
    final feedAsync = searching ? ref.watch(feedProvider) : null;
    final travelAsync =
        searching ? ref.watch(travelFeedProvider(travelQuery)) : null;
    final qaAsync = searching ? ref.watch(qaFeedProvider) : null;

    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final announcement = cfg?.announcement ?? '';
    final maintenance = cfg?.maintenanceMode ?? false;
    final showStories = cfg?.storiesEnabled ?? true;

    // While searching, the mode tabs + search bar are lifted OUT of the
    // scrolling list into a fixed bar so they stay pinned to the top
    // and never scroll away with the results.
    final pinnedTopContent = _searchActive
        ? _topContent(
            announcement: announcement,
            maintenance: maintenance,
            showStories: showStories,
          )
        : const <Widget>[];

    return SafeArea(
      child: Column(
        children: [
          // The tabs row (with the notification bell) is the top of the
          // screen — the old title header was removed. While searching
          // or showing results, the search row stays pinned here.
          if (_searchActive)
            Material(
              // Transparent so the per-tab background shows through —
              // no white strip behind the pinned search row.
              color: Colors.transparent,
              child: Column(children: pinnedTopContent),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: searching
                  ? (_buildSearchResults(
                        feedAsync: feedAsync,
                        travelAsync: travelAsync,
                        qaAsync: qaAsync,
                        topContent: _scrollTopContent(
                          announcement: announcement,
                          maintenance: maintenance,
                          showStories: showStories,
                        ),
                      ) ??
                      ListView(
                        controller: widget.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          ..._scrollTopContent(
                            announcement: announcement,
                            maintenance: maintenance,
                            showStories: showStories,
                          ),
                          const SizedBox(height: 24),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ))
                  : postsAsync.when(
                skipLoadingOnReload: true,
                skipLoadingOnRefresh: true,
                loading: () => ListView(
                  controller: widget.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    ..._scrollTopContent(
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
                    ..._scrollTopContent(
                      announcement: announcement,
                      maintenance: maintenance,
                      showStories: showStories,
                    ),
                    const SizedBox(height: 24),
                    Center(child: Text(context.t.homeErrorPrefix(e))),
                  ],
                ),
                data: (posts) {
                  // Search is handled by the separate all-tabs path
                  // above, so here we just show the current tab's posts.
                  final visiblePosts = posts;

                  if (visiblePosts.isEmpty) {
                    final emptyText = _mode == _HomeMode.qa
                        ? context.t.homeNoDiscussThreads
                        : context.t.homeNoPostsCreateFirst;
                    return ListView(
                      controller: widget.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        ..._scrollTopContent(
                          announcement: announcement,
                          maintenance: maintenance,
                          showStories: showStories,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(emptyText),
                        ),
                      ],
                    );
                  }
                  // Travel mode with no device location → a red/white
                  // banner shown above the first card.
                  final showTravelLocBanner = _mode == _HomeMode.travel &&
                      (_viewerLat == null || _viewerLng == null);

                  return CustomScrollView(
                    controller: widget.scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: _scrollTopContent(
                            announcement: announcement,
                            maintenance: maintenance,
                            showStories: showStories,
                          ),
                        ),
                      ),
                      if (showTravelLocBanner)
                        SliverToBoxAdapter(
                          child: _TravelLocationOffBanner(
                            onEnable: _enableLocationFromBanner,
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        sliver: SliverList.builder(
                          itemCount: visiblePosts.length,
                          itemBuilder: (context, index) {
                            final p = visiblePosts[index];
                            if (_mode == _HomeMode.qa) {
                              return _QaThreadCard(key: ValueKey(p.id), post: p);
                            }
                            final placeLabel = _travelPlaceLabel(p);
                            final hasPlace = placeLabel.isNotEmpty;
                            return PostCard(
                              key: ValueKey(p.id),
                              post: p,
                              travelMode: _mode == _HomeMode.travel,
                              travelPlace: _mode == _HomeMode.travel && hasPlace
                                  ? placeLabel
                                  : null,
                              travelDistance: _mode == _HomeMode.travel
                                  ? (p.travelDistanceLabel ?? '')
                                  : null,
                              // Location-off prompting now lives solely in
                              // the red banner above the feed, so the
                              // per-card prompt is disabled.
                              viewerLocationOff: false,
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

  void _showAskSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AskQuestionSheet(
        onPosted: () {
          ref.invalidate(qaFeedProvider);
        },
      ),
    );
  }

  Future<void> _openCreatePost(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    ref.invalidate(feedProvider);
    ref.invalidate(travelFeedProvider(_buildTravelQuery()));
  }

  String _travelPlaceLabel(Post post) {
    final name = (post.postPlaceName ?? '').trim();
    final city = (post.postPlaceCity ?? '').trim();
    if (name.isEmpty) return city;
    if (city.isEmpty) return name;
    return '$name, $city';
  }
}

class _TravelFilterSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String selected;
  final bool showCurrentLocation;
  final String currentLocationLabel;

  const _TravelFilterSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.showCurrentLocation,
    required this.currentLocationLabel,
  });

  @override
  State<_TravelFilterSheet> createState() => _TravelFilterSheetState();
}

class _TravelFilterSheetState extends State<_TravelFilterSheet> {
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
    final options = <String>[
      _kTravelAllOption,
      if (widget.showCurrentLocation) _kTravelCurrentOption,
      ...widget.options,
    ];
    final allPlacesLabel = context.t.homeAllPlaces;
    final currentLocLabel = context.t.homeCurrentLocation;
    final filtered = _q.isEmpty
        ? options
        : options.where((o) {
            final label = o == _kTravelAllOption
                ? allPlacesLabel
                : o == _kTravelCurrentOption
                    ? '$currentLocLabel · ${widget.currentLocationLabel}'
                    : o;
            return label.toLowerCase().contains(_q);
          }).toList();
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
                      if (widget.selected != _kTravelAllOption)
                        TextButton(
                          onPressed: () => Navigator.pop(context, ''),
                          style: TextButton.styleFrom(
                            foregroundColor: _kTravelFilterPurple,
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
                      hintText: context.t.cityPickerSearchHint,
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
                          color: _kTravelFilterPurple,
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
                          color: _kTravelFilterPurple.withOpacity(0.55),
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
                              context.t.homeNoMatches,
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
                            final label = opt == _kTravelAllOption
                                ? allPlacesLabel
                                : opt == _kTravelCurrentOption
                                    ? '$currentLocLabel · ${widget.currentLocationLabel}'
                                    : opt;
                            final isSel = opt == widget.selected;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Material(
                                color: isSel
                                    ? _kTravelFilterPurple.withOpacity(0.14)
                                    : context.surfaceSoft.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  onTap: () => Navigator.pop(context, opt),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  title: Text(
                                    label,
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
                                          color: _kTravelFilterPurple,
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

/// Filters the Discuss feed. A post matches when its question text
/// (the caption) contains [query], OR its id is in [answerMatches] —
/// the async-resolved set of posts whose answers contain the query.
List<Post> _filterQaPosts(
  List<Post> posts,
  String query,
  Set<String> answerMatches,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return posts;

  return posts.where((post) {
    if (_postMatchesQuery(post, q)) return true;
    return answerMatches.contains(post.id);
  }).toList();
}

/// Filters the main feed by post caption text or location. A query like
/// "Paris" surfaces every post whose city/place is Paris even when the
/// caption never mentions it.
List<Post> _filterFeedPosts(List<Post> posts, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return posts;

  return posts.where((post) => _postMatchesQuery(post, q)).toList();
}

/// True if [post] matches [q]. Caption, place name, and city are all
/// candidates so a city search on Travel ("Erbil") surfaces every post
/// tagged with that location regardless of caption wording.
bool _postMatchesQuery(Post post, String q) {
  if (post.caption.toLowerCase().contains(q)) return true;
  final place = post.postPlaceName?.toLowerCase();
  if (place != null && place.contains(q)) return true;
  final city = post.postPlaceCity?.toLowerCase();
  if (city != null && city.contains(q)) return true;
  return false;
}

/// One row in the global (all-tabs) search result list. Carries the
/// post plus the tab it came from so the right card type is rendered.
class _SearchHit {
  final Post post;
  final _HomeMode origin;
  const _SearchHit(this.post, this.origin);
}

/// Home app-bar: the "Itr" brand title centred, a dropdown next to it
/// to switch between the three modes (Feed / Travel / Discuss), and the
/// notification bell at the trailing edge.
class _HomeModeToggle extends ConsumerWidget {
  final _HomeMode mode;
  final ValueChanged<_HomeMode> onChanged;

  const _HomeModeToggle({
    required this.mode,
    required this.onChanged,
  });

  static const _all = [_HomeMode.feed, _HomeMode.travel, _HomeMode.qa];

  IconData _iconFor(_HomeMode m) {
    switch (m) {
      case _HomeMode.feed:
        return Icons.dynamic_feed_rounded;
      case _HomeMode.travel:
        return Icons.flight;
      case _HomeMode.qa:
        return Icons.forum_outlined;
    }
  }

  String _labelFor(BuildContext context, _HomeMode m) {
    switch (m) {
      case _HomeMode.feed:
        return context.t.homeFeed;
      case _HomeMode.travel:
        return context.t.homeTravelShort;
      case _HomeMode.qa:
        return context.t.homeDiscuss;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // Centred: "Itr" title + the mode dropdown beside it.
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t.headerAppTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ModeDropdown(
                    mode: mode,
                    onChanged: onChanged,
                    all: _all,
                    iconFor: _iconFor,
                    labelFor: (m) => _labelFor(context, m),
                  ),
                ],
              ),
            ),
            // Trailing: notification bell (start side in RTL).
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _NotificationBell(unreadCount: unreadCount),
            ),
          ],
        ),
      ),
    );
  }
}

/// The notification bell with an unread-count badge.
class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  const _NotificationBell({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_outlined,
              size: 26, color: context.textPrimary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationScreen()),
          ),
        ),
        if (unreadCount > 0)
          PositionedDirectional(
            end: 6,
            top: 6,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: AppColors.purple,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pill-shaped dropdown that switches the active home mode. Shows the
/// current mode's icon + name and a chevron; tapping opens a menu with
/// all three modes.
class _ModeDropdown extends StatelessWidget {
  final _HomeMode mode;
  final ValueChanged<_HomeMode> onChanged;
  final List<_HomeMode> all;
  final IconData Function(_HomeMode) iconFor;
  final String Function(_HomeMode) labelFor;

  const _ModeDropdown({
    required this.mode,
    required this.onChanged,
    required this.all,
    required this.iconFor,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_HomeMode>(
      // No `initialValue` — that paints a square selected highlight that
      // breaks out of the rounded menu. We draw our own rounded
      // highlight inside each item instead.
      onSelected: onChanged,
      tooltip: '',
      offset: const Offset(0, 48),
      color: context.cardBg,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      itemBuilder: (context) => [
        for (final m in all)
          PopupMenuItem<_HomeMode>(
            value: m,
            padding: EdgeInsets.zero,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: m == mode
                    ? AppColors.purple.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    iconFor(m),
                    size: 20,
                    color: m == mode
                        ? AppColors.purple
                        : context.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    labelFor(m),
                    style: TextStyle(
                      fontWeight:
                          m == mode ? FontWeight.w700 : FontWeight.w500,
                      color: m == mode
                          ? AppColors.purple
                          : context.textPrimary,
                    ),
                  ),
                  if (m == mode) ...[
                    const Spacer(),
                    const Icon(Icons.check_rounded,
                        size: 18, color: AppColors.purple),
                  ],
                ],
              ),
            ),
          ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.purple, AppColors.purpleVivid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.purple.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(mode), size: 18, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              labelFor(mode),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Red/white banner shown above the first travel card when the
/// device's location is off — prompts the user to enable it.
class _TravelLocationOffBanner extends StatelessWidget {
  final VoidCallback onEnable;

  const _TravelLocationOffBanner({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.t.travelLocationOffBanner,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onEnable,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.red,
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              context.t.travelEnableLocation,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QaThreadCard extends ConsumerWidget {
  final Post post;

  const _QaThreadCard({super.key, required this.post});

  static const List<String> _reportReasons = [
    'Spam or scam',
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Nudity or sexual content',
    'Misinformation',
    'Something else',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final isLiked = ref.watch(isLikedProvider(post.id)).value ?? false;
    final canDelete = currentUid != null && currentUid == post.authorUid;
    final canReport = currentUid != null && currentUid != post.authorUid;
    final caption = post.caption.trim();
    final lines = caption
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title =
        lines.isEmpty ? context.t.qaUntitledQuestion : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    final preview = _twoSentencePreview(body);
    final timeLabel = context.t.timeAgo(post.createdAt);
    final isQuestion = post.discussKind == 'question' ||
        (post.discussKind == null && title.contains('?'));

    void openThread() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QaThreadScreen(post: post),
        ),
      );
    }

    return AppGlassCard(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      radius: 18,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: openThread,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.purpleSoft,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        isQuestion
                            ? Icons.help_outline_rounded
                            : Icons.forum_outlined,
                        size: 18,
                        color: const Color(0xFF7E3BE8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.purpleSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isQuestion
                            ? context.t.homeQuestionLabel
                            : context.t.homeDiscussionLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7E3BE8),
                        ),
                      ),
                    ),
                    if (canDelete || canReport) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: context.t.homeQuestionActions,
                        icon: Icon(Icons.more_horiz,
                            color: context.textSecondary),
                        onSelected: (value) async {
                          if (value == 'report') {
                            await _reportQuestion(context, ref);
                            return;
                          }
                          if (value != 'delete') return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title:
                                  Text(context.t.homeDeleteQuestionTitle),
                              content:
                                  Text(context.t.homeDeleteQuestionBody),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: Text(context.t.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: Text(context.t.delete),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;
                          try {
                            await ref
                                .read(postServiceProvider)
                                .deletePost(post.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      context.t.homeQuestionDeleted)),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      context.t.homeCouldNotDelete(e))),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          if (canReport)
                            PopupMenuItem<String>(
                              value: 'report',
                              child: Row(children: [
                                const Icon(
                                  Icons.flag_outlined,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.t.homeReportQuestionMenu,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ]),
                            ),
                          if (canDelete)
                            PopupMenuItem<String>(
                              value: 'delete',
                              child:
                                  Text(context.t.homeDeleteQuestionMenu),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                // When this discuss item was created from a post, show
                // a mini preview of that post.
                if (post.sourcePostId != null &&
                    post.sourcePostId!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MiniPostPreview(postId: post.sourcePostId!),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QaMeta(
                      icon: Icons.forum_outlined,
                      label: context.t.homeDiscuss,
                      onTap: openThread,
                    ),
                    _QaMeta(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      label: '',
                      highlighted: isLiked,
                      onTap: () async {
                        try {
                          await ref
                              .read(postServiceProvider)
                              .toggleLike(post.id);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    context.t.homeErrorPrefix(e))),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reportQuestion(BuildContext context, WidgetRef ref) async {
    final detailsCtrl = TextEditingController();
    var selectedReason = _reportReasons.first;

    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.cardBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.t.homeReportQuestionMenu,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.pop(sheetContext, false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Text(
                          context.t.homePickReasonQuestion,
                          style: TextStyle(color: context.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        ..._reportReasons.map(
                          (reason) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: reason,
                            groupValue: selectedReason,
                            onChanged: (value) {
                              if (value == null) return;
                              setSheetState(() => selectedReason = value);
                            },
                            title: Text(
                              context.t.reportReasonLabel(reason),
                              style: TextStyle(color: context.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: detailsCtrl,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: context.t.homeExtraDetailsOptional,
                            filled: true,
                            fillColor: context.inputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: context.borderColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, false),
                                child: Text(context.t.cancel),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, true),
                                child: Text(context.t.homeSendReport),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (submitted != true) return;

      await ref.read(postServiceProvider).reportQaPost(
            post: post,
            reason: selectedReason,
            details: detailsCtrl.text,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeReportSentAdmins)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.homeCouldNotReportQuestion(e))),
      );
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => detailsCtrl.dispose());
    }
  }
}

/// Mini preview of the post a Discuss item was created from — shown
/// inside the Discuss home list card. Author line + image + caption
/// in a compact bordered card; tapping it opens the full post.
class _MiniPostPreview extends ConsumerWidget {
  final String postId;

  const _MiniPostPreview({required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(singlePostProvider(postId));

    return postAsync.when(
      loading: () => Container(
        height: 60,
        decoration: BoxDecoration(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (src) {
        if (src == null) return const SizedBox.shrink();
        final hasImage = src.imageUrls.isNotEmpty;
        final cap = src.caption.trim();

        return Material(
          color: context.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(postId: src.id),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              // IntrinsicHeight gives the Row a definite height (the
              // text column's natural height) so the stretched
              // thumbnail has a bounded height — without it, stretch
              // forces infinite height and the layout crashes.
              child: IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thumbnail (if the post has an image).
                  if (hasImage)
                    SizedBox(
                      width: 70,
                      child: CachedNetworkImage(
                        imageUrl: src.imageUrls.first,
                        cacheManager: MediaCache.images,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: context.borderColor),
                      ),
                    ),
                  // Author + caption.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 9,
                                backgroundColor: context.purpleSoft,
                                backgroundImage: (src.authorAvatar != null &&
                                        src.authorAvatar!.isNotEmpty)
                                    ? CachedNetworkImageProvider(
                                        src.authorAvatar!)
                                    : null,
                                child: (src.authorAvatar == null ||
                                        src.authorAvatar!.isEmpty)
                                    ? Icon(Icons.person,
                                        size: 11,
                                        color: context.textSecondary)
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  src.authorUsername,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 16, color: context.textMuted),
                            ],
                          ),
                          if (cap.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              cap,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

String _twoSentencePreview(String text) {
  final normalized = text.replaceAll('\n', ' ').trim();
  if (normalized.isEmpty) return '';
  final parts = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(normalized)
      .map((m) => (m.group(0) ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return normalized;
  return parts.take(2).join(' ');
}

/// Compact row shown under the stories on every home tab. Three
/// states:
///
///   idle      →  [ 🔍 ]············· [ + Post ]
///   searching →  [ 🔍 search input……… ] [ blank tap-to-close ]
///   results   →  [ 🔍 "query…" ]······· [ ✕ ] [ + Post ]
///
/// On Feed / Discuss the search icon expands an inline [TextField].
/// On Travel there is no inline field — tapping the icon calls
/// [onSearchTap] which navigates to the dedicated travel search page.
class _SearchPostRow extends StatelessWidget {
  /// Inline search controller + focus node. Null on Travel (page-based
  /// search), where [onSearchTap] is used instead.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  /// True while the inline search field is focused — drives the
  /// idle/searching/results layout.
  final bool searching;

  /// The active search query. When non-empty and [searching] is false,
  /// the row enters the "results" state: the query shows as a chip and
  /// a ✕ reset button appears before the Post button.
  final String query;

  /// Tap handler for the search icon. On Feed/Discuss this focuses the
  /// inline field; on Travel it opens the travel search page.
  final VoidCallback onSearchTap;

  /// Opens the create-post screen.
  final VoidCallback onPost;

  /// Dismisses the keyboard / unfocuses the search field. Invoked when
  /// the user taps the blank space where the Post button used to be.
  final VoidCallback onDismissSearch;

  const _SearchPostRow({
    required this.hintText,
    required this.searching,
    required this.query,
    required this.onSearchTap,
    required this.onPost,
    required this.onDismissSearch,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? context.inputFill : Colors.white;
    final borderColor = isDark ? Colors.transparent : const Color(0xFFD5D7DF);

    // "results" = a query has been run and the keyboard dismissed.
    final hasResults = !searching && query.isNotEmpty;

    // ── Search side ──────────────────────────────────────────────
    final Widget searchSide;
    if (searching && controller != null) {
      // Expanded inline field (keyboard open).
      searchSide = TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onDismissSearch(),
        // Explicit text color so the typed query is legible in dark
        // mode too.
        style: TextStyle(color: context.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(color: context.textSecondary),
          filled: true,
          fillColor: fieldFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          prefixIcon: Icon(Icons.search, color: context.textSecondary),
          suffixIcon: (controller!.text.isEmpty)
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: Icon(Icons.close,
                      size: 18, color: context.textSecondary),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF7E3BE8), width: 1.2),
          ),
        ),
      );
    } else if (hasResults) {
      // Results state: show the query as a chip. Tapping it re-opens
      // the input for editing.
      searchSide = Material(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSearchTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search, size: 20, color: context.textSecondary),
                const SizedBox(width: 8),
                // The entered query — ellipsized if it is too long.
                Flexible(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Idle: a compact tappable search icon button.
      searchSide = Material(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSearchTap,
          child: Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Icon(Icons.search, color: context.textSecondary),
          ),
        ),
      );
    }

    // ── Post button (shared) ─────────────────────────────────────
    final Widget postButton = PrimaryActionButton(
      label: context.t.post,
      icon: Icons.add,
      onPressed: onPost,
    );

    // ── Reset (✕) button — only in the results state ─────────────
    final Widget resetButton = SizedBox(
      height: 42,
      width: 42,
      child: Material(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onClear,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Icon(Icons.close, size: 20, color: context.textSecondary),
          ),
        ),
      ),
    );

    // ── Assemble the row ─────────────────────────────────────────
    final List<Widget> rowChildren;
    if (searching) {
      // Input fills the row; blank tap-to-dismiss area on the side.
      rowChildren = [
        Expanded(child: searchSide),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismissSearch,
          child: const SizedBox(width: 84, height: 42),
        ),
      ];
    } else if (hasResults) {
      // Query chip fills the row; ✕ reset then + Post on the side.
      rowChildren = [
        Expanded(child: searchSide),
        const SizedBox(width: 8),
        resetButton,
        const SizedBox(width: 8),
        postButton,
      ];
    } else {
      // Idle: compact search icon, spacer, + Post.
      rowChildren = [
        searchSide,
        const Spacer(),
        postButton,
      ];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(children: rowChildren),
    );
  }
}

class _QaMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final VoidCallback? onTap;

  const _QaMeta({
    required this.icon,
    required this.label,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? const Color(0xFF7E3BE8) : context.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted ? context.purpleSoft : context.inputFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Ask Question Sheet
// ─────────────────────────────────────────────

class _AskQuestionSheet extends ConsumerStatefulWidget {
  final VoidCallback onPosted;

  const _AskQuestionSheet({required this.onPosted});

  @override
  ConsumerState<_AskQuestionSheet> createState() => _AskQuestionSheetState();
}

class _AskQuestionSheetState extends ConsumerState<_AskQuestionSheet> {
  final _questionCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _discussKind = 'question';
  bool _submitting = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final question = _questionCtrl.text.trim();
    final details = _detailsCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.homeWriteQuestionFirst)));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(postServiceProvider).createQaPost(
            question: question,
            details: details,
            discussKind: _discussKind,
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted();
    } catch (e) {
      if (e is DiscussPostBlockedException) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.t.homeQuestionBlockedTitle),
            content: Text(context.t.homeQuestionBlockedBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.t.ok),
              ),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.homeErrorPrefix(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset =
        mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom;
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        // Let the sheet grow to fill remaining space so SingleChildScrollView
        // has a bounded height and keyboard insets can be absorbed cleanly.
        margin: EdgeInsets.only(top: mq.size.height * 0.25),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: bottomInset + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.purpleSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: Color(0xFF7E3BE8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.t.homeAskCommunity,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _DiscussKindButton(
                    icon: Icons.help_outline_rounded,
                    label: context.t.homeQuestionLabel,
                    selected: _discussKind == 'question',
                    onTap: () => setState(() => _discussKind = 'question'),
                  ),
                  const SizedBox(width: 8),
                  _DiscussKindButton(
                    icon: Icons.forum_outlined,
                    label: context.t.homeDiscussionLabel,
                    selected: _discussKind == 'discussion',
                    onTap: () => setState(() => _discussKind = 'discussion'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Question field
              TextField(
                controller: _questionCtrl,
                autofocus: true,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _discussKind == 'discussion'
                      ? context.t.homeWhatsYourDiscussion
                      : context.t.homeWhatsYourQuestion,
                  hintStyle: TextStyle(
                      color: context.textSecondary,
                      fontWeight: FontWeight.w400),
                  filled: true,
                  fillColor: context.inputFill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Optional details field
              TextField(
                controller: _detailsCtrl,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 14, color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: context.t.homeAddMoreContext,
                  hintStyle: TextStyle(color: context.textSecondary),
                  filled: true,
                  fillColor: context.inputFill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryActionButton(
                label: _discussKind == 'discussion'
                    ? context.t.homePostDiscussion
                    : context.t.homePostQuestion,
                onPressed: _submitting ? null : _submit,
                loading: _submitting,
                size: PrimaryActionSize.large,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscussKindButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DiscussKindButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF7E3BE8) : context.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.purpleSoft : context.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF7E3BE8).withValues(alpha: 0.35)
                  : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
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
  late final TextEditingController _cityCtrl;
  late final TextEditingController _countryCtrl;
  Timer? _debounce;
  List<TravelPlaceResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cityCtrl = TextEditingController();
    _countryCtrl = TextEditingController();

    final query = (widget.currentPlace?.queryText ?? '').trim();
    if (query.isNotEmpty) {
      final parts = query.split(',');
      _cityCtrl.text = parts.first.trim();
      if (parts.length > 1) {
        _countryCtrl.text = parts.sublist(1).join(',').trim();
      }
    }
    _loadPlaces();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    final city = _cityCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final query = [city, country].where((v) => v.isNotEmpty).join(' ');

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(postServiceProvider).searchTravelPlaces(
            query: query,
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
    final hasCity = _cityCtrl.text.trim().isNotEmpty;
    final hasCountry = _countryCtrl.text.trim().isNotEmpty;
    return Container(
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _cityCtrl,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_city, size: 18),
                      hintText: context.t.homeFilterByCity,
                      hintStyle: TextStyle(color: context.textSecondary),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                  Divider(height: 1, color: context.borderColor),
                  TextField(
                    controller: _countryCtrl,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.public, size: 18),
                      hintText: context.t.homeFilterByCountry,
                      hintStyle: TextStyle(color: context.textSecondary),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasCity || hasCountry)
            IconButton(
              onPressed: () {
                _cityCtrl.clear();
                _countryCtrl.clear();
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
    if (oldWidget.currentPlace?.queryText != widget.currentPlace?.queryText) {
      final query = (widget.currentPlace?.queryText ?? '').trim();
      final parts = query.split(',');
      _cityCtrl.text = parts.first.trim();
      _countryCtrl.text =
          parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
      _loadPlaces();
    }
  }

  _PlaceSuggestion _placeFromResult(TravelPlaceResult p) {
    final queryText = p.city.trim().isEmpty ? p.name.trim() : p.city.trim();
    return _PlaceSuggestion(
      name: queryText,
      city: '',
      lat: p.lat,
      lng: p.lng,
      queryText: queryText,
    );
  }

  _PlaceSuggestion _typedFilter(BuildContext context) {
    final city = _cityCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final query = [city, country].where((v) => v.isNotEmpty).join(', ');
    return _PlaceSuggestion(
      name: query.isEmpty ? context.t.homeAllPlaces : query,
      city: '',
      queryText: query,
    );
  }

  Widget _allPlacesCard(BuildContext context) {
    final allPlacesLabel = context.t.homeAllPlaces;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(
          context,
          _PlaceSuggestion(
            name: allPlacesLabel,
            city: '',
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
                child: const Icon(Icons.public,
                    size: 18, color: Color(0xFF7E3BE8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allPlacesLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.homeDefaultShowTravel,
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

  Widget _currentLocationCard(BuildContext context) {
    final useCurrentLabel = context.t.homeUseMyCurrentLocation;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(
          context,
          _PlaceSuggestion(
            name: useCurrentLabel,
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
                      useCurrentLabel,
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
    final city = _cityCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final hasQuery = city.isNotEmpty || country.isNotEmpty;
    final typedFilter = _typedFilter(context);

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
                    context.t.homeTravelFilterTitle,
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
              _allPlacesCard(context),
              const SizedBox(height: 10),
              _currentLocationCard(context),
              const SizedBox(height: 14),
              if (hasQuery)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, typedFilter),
                      icon: const Icon(Icons.tune),
                      label: Text(
                        context.t.homeApplyFilter(typedFilter.queryText ?? ''),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
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
                                  context.t.homeNoPlacesFoundTravel,
                                  style:
                                      TextStyle(color: context.textSecondary),
                                ),
                              )
                            : ListView(
                                children: [
                                  if (!hasQuery &&
                                      widget.recents.isNotEmpty) ...[
                                    Text(
                                      context.t.homeRecent,
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
                                        ? context.t.homeMatchingPlaces
                                        : context.t.homePopularCitiesCountries,
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
                                          p.city.isEmpty ? p.name : p.city,
                                          style: TextStyle(
                                            color: context.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          p.city.isEmpty
                                              ? context.t.homeUnknownCityCountry
                                              : context.t.homeFromTravelPosts,
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
              context.t.homeMaintenanceMode,
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
            label: context.t.homeAllPlaces,
            icon: Icons.public,
            selected: isAll,
            onTap: onSelectAll,
          ),
          const SizedBox(width: 6),
          _TravelFilterChip(
            label: viewerCity.isNotEmpty
                ? context.t.homeNearbyCity(viewerCity)
                : context.t.homeNearby,
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
    final bg = disabled
            ? context.inputFill.withValues(alpha: 0.5)
            : context.inputFill;
    final fg = selected
        ? Colors.white
        : (disabled ? context.textMuted : context.textPrimary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? null : bg,
          gradient: selected
              ? const LinearGradient(
                  colors: [AppColors.purple, AppColors.purpleVivid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.transparent,
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.purple.withValues(alpha: 0.30),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
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
