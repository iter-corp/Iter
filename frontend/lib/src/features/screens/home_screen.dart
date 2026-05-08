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
import 'create_post_screen.dart';
import 'qa_thread_screen.dart';
import '../widgets/header.dart';
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
  final TextEditingController _qaSearchCtrl = TextEditingController();
  String _qaSearch = '';
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

  @override
  void dispose() {
    _qaSearchCtrl.dispose();
    super.dispose();
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

    if (mode == _HomeMode.qa) {
      ref.invalidate(qaFeedProvider);
      try {
        await ref.read(qaFeedProvider.future);
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
        _TravelPromptStrip(onPost: () => _openCreatePost(context)),
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
      ] else if (_mode == _HomeMode.qa) ...[
        _QaPromptStrip(onAsk: () => _showAskSheet(context)),
        _QaSearchBar(
          controller: _qaSearchCtrl,
          onChanged: (value) => setState(() => _qaSearch = value.trim()),
          onClear: () {
            _qaSearchCtrl.clear();
            setState(() => _qaSearch = '');
          },
        ),
      ] else ...[
        _FeedPromptStrip(onPost: () => _openCreatePost(context)),
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
        : _mode == _HomeMode.qa
            ? ref.watch(qaFeedProvider)
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
                  final visiblePosts = _mode == _HomeMode.qa
                      ? _filterQaPosts(posts, _qaSearch)
                      : posts;

                  if (visiblePosts.isEmpty) {
                    final emptyText = _mode == _HomeMode.qa
                        ? (_qaSearch.isEmpty
                            ? 'No Q&A threads yet. Ask the first question!'
                            : 'No matching questions found.')
                        : 'No posts yet. Create the first one!';
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
                        Center(
                          child: Text(emptyText),
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
                          itemCount: visiblePosts.length,
                          itemBuilder: (context, index) {
                            final p = visiblePosts[index];
                            if (_mode == _HomeMode.qa) {
                              return _QaThreadCard(post: p);
                            }
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

List<Post> _filterQaPosts(List<Post> posts, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return posts;

  return posts.where((post) {
    final caption = post.caption.toLowerCase();
    final author = post.authorUsername.toLowerCase();
    return caption.contains(q) || author.contains(q);
  }).toList();
}

class _HomeModeToggle extends StatelessWidget {
  final _HomeMode mode;
  final ValueChanged<_HomeMode> onChanged;

  const _HomeModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cardBg = context.cardBg;
    final trackColor = context.inputFill;
    final selectedIndex = mode == _HomeMode.feed
        ? 0
        : mode == _HomeMode.travel
            ? 1
            : 2;
    const flexes = [10.0, 12.0, 10.0];
    const totalFlex = 32.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // Row: SizedBox(2) + Expanded*3 + SizedBox(6)*2 + SizedBox(2)
            final flexWidth = available - 2 - 6 - 6 - 2;
            final w = flexes.map((f) => flexWidth * f / totalFlex).toList();
            final x = [
              2.0,
              2.0 + w[0] + 6,
              2.0 + w[0] + 6 + w[1] + 6,
            ];
            return SizedBox(
              height: 44,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    left: x[selectedIndex],
                    width: w[selectedIndex],
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.borderColor),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 2),
                      Expanded(
                        flex: 10,
                        child: _ModePillButton(
                          label: 'Feed',
                          icon: Icons.dynamic_feed_rounded,
                          selected: mode == _HomeMode.feed,
                          onTap: () => onChanged(_HomeMode.feed),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 12,
                        child: _ModePillButton(
                          label: 'Travel Mode',
                          icon: Icons.flight,
                          selected: mode == _HomeMode.travel,
                          selectedHorizontalPadding: 10,
                          onTap: () => onChanged(_HomeMode.travel),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 10,
                        child: _ModePillButton(
                          label: 'Q&A',
                          icon: Icons.forum_outlined,
                          selected: mode == _HomeMode.qa,
                          onTap: () => onChanged(_HomeMode.qa),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QaThreadCard extends ConsumerWidget {
  final Post post;

  const _QaThreadCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
    final isLiked = ref.watch(isLikedProvider(post.id)).value ?? false;
    final canDelete = currentUid != null && currentUid == post.authorUid;
    final caption = post.caption.trim();
    final lines = caption
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title = lines.isEmpty ? 'Untitled question' : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    final preview = _twoSentencePreview(body);
    final timeLabel = _relativeTime(post.createdAt);
    final isQuestion = title.contains('?');

    void openThread() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QaThreadScreen(post: post),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: openThread,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: context.isDark ? 0.12 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
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
                            '$timeLabel ago',
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
                        isQuestion ? 'Question' : 'Discussion',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7E3BE8),
                        ),
                      ),
                    ),
                    if (canDelete) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Question actions',
                        icon: Icon(Icons.more_horiz,
                            color: context.textSecondary),
                        onSelected: (value) async {
                          if (value != 'delete') return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Delete question?'),
                              content: const Text(
                                'This will permanently remove your question from Q&A.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Delete'),
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
                              const SnackBar(content: Text('Question deleted')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not delete: $e')),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete question'),
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QaMeta(
                      icon: Icons.chat_bubble_outline,
                      label: '${post.commentsCount} answers',
                      onTap: openThread,
                    ),
                    _QaMeta(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      label: '${post.likesCount} helpful',
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
                                content: Text('Could not like question: $e')),
                          );
                        }
                      },
                    ),
                    _QaMeta(
                      icon: Icons.edit_outlined,
                      label: 'Write answer',
                      onTap: openThread,
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

class _QaPromptStrip extends StatelessWidget {
  final VoidCallback onAsk;
  const _QaPromptStrip({required this.onAsk});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDark
              ? const [Color(0xFF2B2638), Color(0xFF252333)]
              : const [Color(0xFFF8F1FF), Color(0xFFF3F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF4A4066)
              : const Color(0xFFDCC8E6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: const Icon(
              Icons.question_answer_rounded,
              size: 20,
              color: Color(0xFF7E3BE8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Have a question? Ask the community',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Get quick answers from people nearby.',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: onAsk,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Ask'),
          ),
        ],
      ),
    );
  }
}

class _FeedPromptStrip extends StatelessWidget {
  final VoidCallback onPost;

  const _FeedPromptStrip({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDark
              ? const [Color(0xFF23303A), Color(0xFF202A34)]
              : const [Color(0xFFEFF9FF), Color(0xFFF3F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF395168)
              : const Color(0xFFC9DDEE),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: const Icon(
              Icons.dynamic_feed_rounded,
              size: 20,
              color: Color(0xFF2F7CA8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Got something to share? Post it',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Share updates, photos, and moments with your feed.',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: onPost,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

class _TravelPromptStrip extends StatelessWidget {
  final VoidCallback onPost;

  const _TravelPromptStrip({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDark
              ? const [Color(0xFF2B3125), Color(0xFF253026)]
              : const [Color(0xFFF2FFE9), Color(0xFFEAF9FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF4A6143)
              : const Color(0xFFCFE6C2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: const Icon(
              Icons.explore_rounded,
              size: 20,
              color: Color(0xFF3E8B44),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Traveling somewhere? Post from there',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Share place-based moments others can discover.',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: onPost,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

class _QaSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _QaSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search questions or users...',
          prefixIcon: Icon(Icons.search, color: context.textSecondary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear search',
                ),
        ),
      ),
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
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime? dt) {
  if (dt == null) return 'just now';
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 30) return '${diff.inDays}d';
  final months = (diff.inDays / 30).floor();
  if (months < 12) return '${months}mo';
  return '${(months / 12).floor()}y';
}

class _ModePillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final double selectedHorizontalPadding;
  final VoidCallback onTap;

  const _ModePillButton({
    required this.label,
    this.icon,
    required this.selected,
    this.selectedHorizontalPadding = 8,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          vertical: 10,
          horizontal: selected ? selectedHorizontalPadding : 8,
        ),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected && icon != null) ...[
              Icon(icon, size: 16, color: context.textPrimary),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
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
  bool _submitting = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write your question first')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(postServiceProvider).createQaPost(
            question: question,
            details: _detailsCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                    'Ask the community',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                  hintText: "What's your question?",
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
                  hintText: 'Add more context (optional)...',
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
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7E3BE8),
                    disabledBackgroundColor:
                        const Color(0xFF7E3BE8).withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Post Question',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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
