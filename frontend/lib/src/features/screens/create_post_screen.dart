import 'dart:io';

import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/post_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../widgets/location_map.dart';
import 'camera_story_screen.dart';
import 'live_screen.dart';

String _normalizeCitySearch(String input) {
  var out = removeDiacritics(input).toLowerCase().trim();
  const replacements = {
    'ı': 'i',
    'İ': 'i',
    'ñ': 'n',
    'ç': 'c',
    'ş': 's',
    'ğ': 'g',
    'ý': 'y',
    'ÿ': 'y',
    'æ': 'ae',
    'œ': 'oe',
  };
  replacements.forEach((from, to) {
    out = out.replaceAll(from, to);
  });
  out = out.replaceAll(RegExp(r"[^a-z0-9\s-]"), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _captionCtrl = TextEditingController();
  final _placeNameCtrl = TextEditingController();
  final _placeCityCtrl = TextEditingController();
  final List<File> _pickedImages = [];
  static List<_CityOption>? _cachedWorldCities;
  List<_CityOption> _worldCities = const [];
  bool _worldCitiesLoading = false;
  bool _isPrivate = false;
  bool _posting = false;
  double? _placeLat;
  double? _placeLng;
  bool _placeFromCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    _ensureWorldCitiesLoaded();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _placeNameCtrl.dispose();
    _placeCityCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureWorldCitiesLoaded() async {
    if (_cachedWorldCities != null) {
      _worldCities = _cachedWorldCities!;
      return;
    }

    if (mounted) {
      setState(() => _worldCitiesLoading = true);
    }
    try {
      final all = await csc.getAllCities();
      final dedup = <String, _CityOption>{};
      for (final city in all) {
        final name = city.name.trim();
        if (name.isEmpty) continue;
        final country = city.countryCode.trim();
        final state = city.stateCode.trim();
        final key =
            '${name.toLowerCase()}|${country.toLowerCase()}|${state.toLowerCase()}';
        final normalizedName = _normalizeCitySearch(name);
        final searchHaystack = _normalizeCitySearch('$name $country $state');
        dedup[key] = _CityOption(
          name: name,
          countryCode: country,
          stateCode: state,
          normalizedName: normalizedName,
          searchHaystack: searchHaystack,
        );
      }
      final out = dedup.values.toList()
        ..sort((a, b) {
          final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          if (byName != 0) return byName;
          final byCountry = a.countryCode
              .toLowerCase()
              .compareTo(b.countryCode.toLowerCase());
          if (byCountry != 0) return byCountry;
          return a.stateCode.toLowerCase().compareTo(b.stateCode.toLowerCase());
        });
      _cachedWorldCities = out;
      if (!mounted) return;
      setState(() => _worldCities = out);
    } catch (_) {
      if (!mounted) return;
      setState(() => _worldCities = const []);
    } finally {
      if (mounted) {
        setState(() => _worldCitiesLoading = false);
      }
    }
  }

  Future<void> _useCurrentLocationForPlace() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw 'Location services are off. Enable them in device settings.';
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      String city = _placeCityCtrl.text.trim();
      String place = _placeNameCtrl.text.trim();
      try {
        final marks =
            await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          city = (p.locality ?? p.subAdministrativeArea ?? city).trim();
          final nameParts = <String>[
            p.name ?? '',
            p.street ?? '',
          ].where((v) => v.trim().isNotEmpty).toList();
          if (nameParts.isNotEmpty) {
            place = nameParts.first.trim();
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _placeLat = pos.latitude;
        _placeLng = pos.longitude;
        _placeFromCurrentLocation = true;
        if (city.isNotEmpty) _placeCityCtrl.text = city;
        if (place.isNotEmpty) {
          _placeNameCtrl.text = place;
        } else if (_placeNameCtrl.text.trim().isEmpty) {
          _placeNameCtrl.text = 'Current location';
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Geocode whatever the user typed in the place / city fields and
  /// drop a pin on the map. Lets users post a location they're not
  /// currently standing in (e.g. a place they want to recommend).
  Future<void> _locateTypedPlaceOnMap() async {
    final name = _placeNameCtrl.text.trim();
    final city = _placeCityCtrl.text.trim();
    final query = [name, city].where((s) => s.isNotEmpty).join(', ');
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type a place name or city first'),
        ),
      );
      return;
    }
    try {
      final results = await geo.locationFromAddress(query);
      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No coordinates found for "$query"')),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _placeLat = results.first.latitude;
        _placeLng = results.first.longitude;
        _placeFromCurrentLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lookup failed: $e')),
      );
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickMultiImage(imageQuality: 85, maxWidth: 1600);
    if (picked.isEmpty) return;
    setState(() {
      _pickedImages.addAll(picked.map((x) => File(x.path)));
    });
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    setState(() => _pickedImages.add(File(picked.path)));
  }

  Future<void> _openCityPicker() async {
    if (_cachedWorldCities == null && !_worldCitiesLoading) {
      await _ensureWorldCitiesLoaded();
    }

    final selectedCity = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CityPickerSheet(
        initialQuery: _placeCityCtrl.text.trim(),
        cities: _cachedWorldCities ?? _worldCities,
        loading: _worldCitiesLoading,
      ),
    );

    if (!mounted || selectedCity == null) return;
    setState(() {
      _placeCityCtrl.text = selectedCity;
      if (_placeFromCurrentLocation) {
        _placeFromCurrentLocation = false;
      }
    });
  }

  void _removeImage(int i) {
    setState(() => _pickedImages.removeAt(i));
  }

  Future<void> _submit() async {
    final caption = _captionCtrl.text.trim();
    final placeName = _placeNameCtrl.text.trim();
    final placeCity = _placeCityCtrl.text.trim();
    if (caption.isEmpty && _pickedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a caption or image')),
      );
      return;
    }
    // Capture the messenger up-front so the success toast survives popping
    // this route after the post is created.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _posting = true);
    try {
      // If place name is entered but coordinates aren't set, geocode the place
      double? finalLat = _placeLat;
      double? finalLng = _placeLng;
      if (placeName.isNotEmpty && (finalLat == null || finalLng == null)) {
        try {
          final query =
              placeCity.isNotEmpty ? '$placeName, $placeCity' : placeName;
          final locations = await geo.locationFromAddress(query);
          if (locations.isNotEmpty) {
            finalLat = locations.first.latitude;
            finalLng = locations.first.longitude;
          }
        } catch (_) {
          // Geocoding failed, continue without coordinates
        }
      }

      final storage = StorageService();
      final urls = <String>[];
      for (final file in _pickedImages) {
        urls.add(await storage.uploadPostImage(file));
      }

      await ref.read(postServiceProvider).createPost(
            caption: caption,
            imageUrls: urls,
            isPrivate: _isPrivate,
            postPlaceName: placeName,
            postPlaceCity: placeCity,
            postLat: finalLat,
            postLng: finalLng,
            postLocationExact: _placeFromCurrentLocation &&
                finalLat != null &&
                finalLng != null,
          );
      if (mounted) {
        Navigator.pop(context);
        AppFeedback.showSuccessOn(
          messenger,
          urls.isNotEmpty
              ? 'Post published — content uploaded'
              : 'Post published',
        );
      }
    } catch (e) {
      if (e is PostBlockedException) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Post blocked'),
              content: const Text(
                'You cannot publish this post because its caption or place fields contain blocked words.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
      if (mounted) {
        AppFeedback.showError(context, 'Could not publish post: $e');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserDocProvider).value;
    final username = (user?['username'] as String?) ?? '';
    final avatarUrl = user?['avatarUrl'] as String?;

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 26),
                    ),
                    const Expanded(
                      child: Text(
                        'New post',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    _PostButton(loading: _posting, onTap: _submit),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // AUTHOR ROW
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: context.inputFill,
                            backgroundImage: avatarUrl != null
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null
                                ? Icon(Icons.person,
                                    size: 22, color: context.textMuted)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username.isEmpty ? 'You' : username,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                _PrivacyChip(
                                  isPrivate: _isPrivate,
                                  onTap: () =>
                                      setState(() => _isPrivate = !_isPrivate),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // CAPTION CARD
                      Container(
                        decoration: BoxDecoration(
                          color: context.inputFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.borderColor),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: TextField(
                          controller: _captionCtrl,
                          maxLines: 6,
                          minLines: 3,
                          style: TextStyle(
                              fontSize: 15, color: context.textPrimary),
                          decoration: InputDecoration(
                            hintText: "What's happening? Share your moment…",
                            hintStyle: TextStyle(
                              color: context.textSecondary,
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            isCollapsed: true,
                            filled: false,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.borderColor),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Place',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PostFormField(
                              controller: _placeNameCtrl,
                              hintText: 'Place name (optional)',
                              icon: Icons.place_outlined,
                              onChanged: (_) {
                                if (_placeFromCurrentLocation) {
                                  setState(
                                      () => _placeFromCurrentLocation = false);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            _CityDropdownField(
                              controller: _placeCityCtrl,
                              hintText: 'Select city (optional)',
                              icon: Icons.location_city_outlined,
                              onTap: _openCityPicker,
                              onClear: () {
                                setState(() {
                                  _placeCityCtrl.clear();
                                  if (_placeFromCurrentLocation) {
                                    _placeFromCurrentLocation = false;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _useCurrentLocationForPlace,
                                    icon: const Icon(Icons.my_location_rounded),
                                    label: const Text(
                                      'Use current location',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _locateTypedPlaceOnMap,
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text(
                                      'Locate on map',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_placeLat != null && _placeLng != null) ...[
                              const SizedBox(height: 10),
                              MapPreview(
                                lat: _placeLat!,
                                lng: _placeLng!,
                                label: _placeNameCtrl.text.trim().isEmpty
                                    ? null
                                    : _placeNameCtrl.text.trim(),
                                subtitle: _placeCityCtrl.text.trim().isEmpty
                                    ? null
                                    : _placeCityCtrl.text.trim(),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // IMAGE GRID
                      if (_pickedImages.isNotEmpty)
                        _ImageGrid(
                          files: _pickedImages,
                          onRemove: _removeImage,
                        ),
                      if (_pickedImages.isNotEmpty) const SizedBox(height: 16),

                      // ACTION TILES
                      _ActionTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Photo from gallery',
                        onTap: _pickImages,
                      ),
                      const SizedBox(height: 8),
                      _ActionTile(
                        icon: Icons.camera_alt_outlined,
                        label: 'Take a photo',
                        onTap: _pickFromCamera,
                      ),
                    ],
                  ),
                ),
              ),

              // BOTTOM PILL TABS
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.surfaceSoft,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _bottomTab('Post', 0, true),
                        _bottomTab('Story', 1, false),
                      ],
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

  Widget _bottomTab(String text, int index, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CameraStoryScreen()),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? context.textPrimary : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PostButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _PostButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD044E8), Color(0xFF7E3BE8)],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD044E8).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                'Post',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  final bool isPrivate;
  final VoidCallback onTap;
  const _PrivacyChip({required this.isPrivate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isPrivate ? context.purpleSoft : context.purpleSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPrivate
                ? const Color(0xFFD044E8).withValues(alpha: 0.4)
                : const Color(0xFF7E3BE8).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPrivate ? Icons.lock_outline : Icons.public,
              size: 12,
              color:
                  isPrivate ? const Color(0xFFD044E8) : const Color(0xFF7E3BE8),
            ),
            const SizedBox(width: 4),
            Text(
              isPrivate ? 'Followers only' : 'Public',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isPrivate
                    ? const Color(0xFFD044E8)
                    : const Color(0xFF7E3BE8),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: Color(0xFF7E3BE8)),
          ],
        ),
      ),
    );
  }
}

class _PostFormField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  const _PostFormField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.borderColor,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF7E3BE8)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: context.textSecondary),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CityDropdownField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _CityDropdownField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final value = controller.text.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: context.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF7E3BE8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value.isEmpty ? hintText : value,
                  style: TextStyle(
                    color: value.isEmpty
                        ? context.textSecondary
                        : context.textPrimary,
                  ),
                ),
              ),
              if (value.isNotEmpty)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: context.textSecondary,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityPickerSheet extends StatefulWidget {
  final String initialQuery;
  final List<_CityOption> cities;
  final bool loading;

  const _CityPickerSheet({
    required this.initialQuery,
    required this.cities,
    required this.loading,
  });

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late final TextEditingController _searchCtrl;
  List<_CityOption> _filteredCities = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    _filterCities();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterCities() {
    final rawQuery = _searchCtrl.text;
    final q = _normalizeCitySearch(rawQuery);
    if (q.isEmpty) {
      setState(() => _filteredCities = widget.cities);
      return;
    }

    final ranked = <({int score, int lenDelta, _CityOption city})>[];
    for (final city in widget.cities) {
      if (!city.searchHaystack.contains(q)) continue;

      int score;
      if (city.normalizedName == q) {
        score = 0;
      } else if (city.normalizedName.startsWith(q)) {
        score = 1;
      } else if (city.normalizedName
          .split(RegExp(r'[\s-]+'))
          .any((part) => part.startsWith(q))) {
        score = 2;
      } else {
        score = 3;
      }

      ranked.add((
        score: score,
        lenDelta: (city.normalizedName.length - q.length).abs(),
        city: city,
      ));
    }

    ranked.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      final byLen = a.lenDelta.compareTo(b.lenDelta);
      if (byLen != 0) return byLen;
      final byName =
          a.city.name.toLowerCase().compareTo(b.city.name.toLowerCase());
      if (byName != 0) return byName;
      return a.city.countryCode
          .toLowerCase()
          .compareTo(b.city.countryCode.toLowerCase());
    });

    setState(
      () => _filteredCities = ranked.map((item) => item.city).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => _filterCities(),
                decoration: InputDecoration(
                  hintText: 'Search city',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: widget.loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredCities.isEmpty
                        ? Center(
                            child: Text(
                              'No cities found',
                              style: TextStyle(color: context.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredCities.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: context.borderColor,
                            ),
                            itemBuilder: (_, index) {
                              final city = _filteredCities[index];
                              return ListTile(
                                title: Text(city.name),
                                subtitle: city.countryCode.isEmpty &&
                                        city.stateCode.isEmpty
                                    ? null
                                    : Text(
                                        [city.stateCode, city.countryCode]
                                            .where((s) => s.isNotEmpty)
                                            .join(' • '),
                                      ),
                                onTap: () => Navigator.pop(context, city.name),
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

class _CityOption {
  final String name;
  final String countryCode;
  final String stateCode;
  final String normalizedName;
  final String searchHaystack;

  const _CityOption({
    required this.name,
    required this.countryCode,
    required this.stateCode,
    required this.normalizedName,
    required this.searchHaystack,
  });
}

class _ImageGrid extends StatelessWidget {
  final List<File> files;
  final ValueChanged<int> onRemove;
  const _ImageGrid({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: files.length,
      itemBuilder: (_, i) => Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(files[i], fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => onRemove(i),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(3),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.purpleSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF7E3BE8)),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Color(0xFFB1B1B6)),
            ],
          ),
        ),
      ),
    );
  }
}
