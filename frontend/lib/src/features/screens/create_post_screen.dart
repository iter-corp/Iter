import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/city_service.dart';
import '../../services/post_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../widgets/location_map.dart';
import 'camera_story_screen.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

// Max upload size per video. Keep in sync with backend storage rules.
const int _maxVideoBytes = 30 * 1024 * 1024;

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _captionCtrl = TextEditingController();
  final _placeNameCtrl = TextEditingController();
  final _placeCityCtrl = TextEditingController();
  final List<File> _pickedImages = [];
  final List<File> _pickedVideos = [];
  bool _isPrivate = false;
  bool _posting = false;
  // One-shot guard so the "followers-only by default for private
  // accounts" rule only runs once per screen mount — otherwise the
  // user couldn't manually flip to Public, because every rebuild
  // would force the chip back to followers-only.
  bool _privacyDefaultApplied = false;
  double? _placeLat;
  double? _placeLng;
  bool _placeFromCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    // Warm the shared world-city list so the picker opens instantly.
    Future.microtask(() => ref.read(worldCitiesProvider.future));
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _placeNameCtrl.dispose();
    _placeCityCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocationForPlace() async {
    final servicesOffMsg = context.t.createPostLocationServicesOff;
    final permissionDeniedMsg = context.t.createPostLocationPermissionDenied;
    final currentLocationLabel = context.t.createPostCurrentLocation;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw servicesOffMsg;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw permissionDeniedMsg;
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
          _placeNameCtrl.text = currentLocationLabel;
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
        SnackBar(
          content: Text(context.t.createPostTypePlaceFirst),
        ),
      );
      return;
    }
    try {
      final results = await geo.locationFromAddress(query);
      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.t.createPostNoCoordinates(query))),
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
        SnackBar(content: Text(context.t.createPostLookupFailed(e))),
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

  Future<void> _pickVideoFromGallery() async {
    debugPrint('[CreatePost] _pickVideoFromGallery start');
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null) {
      debugPrint('[CreatePost] gallery pick cancelled (null)');
      return;
    }
    final f = File(picked.path);
    if (!await _ensureVideoUnderLimit(f, 'gallery')) return;
    setState(() => _pickedVideos.add(f));
  }

  Future<void> _pickVideoFromCamera() async {
    debugPrint('[CreatePost] _pickVideoFromCamera start');
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null) {
      debugPrint('[CreatePost] camera pick cancelled (null)');
      return;
    }
    final f = File(picked.path);
    if (!await _ensureVideoUnderLimit(f, 'camera')) return;
    setState(() => _pickedVideos.add(f));
  }

  /// Rejects video files larger than [_maxVideoBytes] and shows the user
  /// a clear message. Returns true when the file is OK to add.
  Future<bool> _ensureVideoUnderLimit(File f, String source) async {
    final exists = await f.exists();
    final size = exists ? await f.length() : -1;
    debugPrint('[CreatePost] $source picked path=${f.path} '
        'exists=$exists size=$size');
    if (!exists || size <= 0) {
      if (mounted) {
        AppFeedback.showError(
            context, context.t.createPostCouldNotReadVideo);
      }
      return false;
    }
    if (size > _maxVideoBytes) {
      final mb = (size / (1024 * 1024)).toStringAsFixed(1);
      debugPrint('[CreatePost] rejected oversize video: ${mb}MB > 30MB');
      if (mounted) {
        AppFeedback.showError(
          context,
          context.t.createPostVideoTooLarge(mb),
        );
      }
      return false;
    }
    return true;
  }

  void _removeImage(int i) {
    setState(() => _pickedImages.removeAt(i));
  }

  void _removeVideo(int i) {
    setState(() => _pickedVideos.removeAt(i));
  }

  Future<void> _submit() async {
    final caption = _captionCtrl.text.trim();
    final placeName = _placeNameCtrl.text.trim();
    final placeCity = _placeCityCtrl.text.trim();
    if (caption.isEmpty && _pickedImages.isEmpty && _pickedVideos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.t.createPostAddCaptionImageVideo)),
      );
      return;
    }
    // Capture the messenger up-front so the success toast survives popping
    // this route after the post is created.
    final messenger = ScaffoldMessenger.of(context);
    final publishedWithContentMsg = context.t.createPostPublishedWithContent;
    final publishedMsg = context.t.createPostPublished;
    final t = context.t;
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

      debugPrint('[CreatePost] _submit start '
          'images=${_pickedImages.length} videos=${_pickedVideos.length} '
          'captionLen=${caption.length} isPrivate=$_isPrivate');

      final storage = StorageService();
      final urls = <String>[];
      for (final file in _pickedImages) {
        debugPrint('[CreatePost] uploading image path=${file.path}');
        urls.add(await storage.uploadPostImage(file));
      }
      debugPrint('[CreatePost] image upload phase done, count=${urls.length}');

      final videoUrls = <String>[];
      for (var i = 0; i < _pickedVideos.length; i++) {
        final file = _pickedVideos[i];
        debugPrint('[CreatePost] uploading video '
            '${i + 1}/${_pickedVideos.length} path=${file.path}');
        try {
          final url = await storage.uploadPostVideo(file);
          debugPrint('[CreatePost] video ${i + 1} uploaded url=$url');
          videoUrls.add(url);
        } catch (e, st) {
          debugPrint('[CreatePost] video ${i + 1} upload FAILED: $e\n$st');
          rethrow;
        }
      }
      debugPrint('[CreatePost] video upload phase done, '
          'count=${videoUrls.length}');

      debugPrint('[CreatePost] calling createPost…');
      await ref.read(postServiceProvider).createPost(
            caption: caption,
            imageUrls: urls,
            videoUrls: videoUrls,
            isPrivate: _isPrivate,
            postPlaceName: placeName,
            postPlaceCity: placeCity,
            postLat: finalLat,
            postLng: finalLng,
            postLocationExact: _placeFromCurrentLocation &&
                finalLat != null &&
                finalLng != null,
          );
      debugPrint('[CreatePost] createPost OK');
      if (mounted) {
        Navigator.pop(context);
        AppFeedback.showSuccessOn(
          messenger,
          (urls.isNotEmpty || videoUrls.isNotEmpty)
              ? publishedWithContentMsg
              : publishedMsg,
        );
      }
    } catch (e, st) {
      debugPrint('[CreatePost] _submit FAILED: $e\n$st');
      if (e is PostBlockedException) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(context.t.createPostBlockedTitle),
              content: Text(context.t.createPostBlockedBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.t.ok),
                ),
              ],
            ),
          );
        }
        return;
      }
      if (mounted) {
        AppFeedback.showError(context, t.createPostCouldNotPublish(e));
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

    // First time the user doc resolves: if the account is private,
    // default this post's audience to followers-only. The user can
    // still tap the privacy chip to switch to Public for an individual
    // post — the guard makes sure we don't keep overriding their choice
    // on every rebuild.
    if (!_privacyDefaultApplied && user != null) {
      _privacyDefaultApplied = true;
      final accountIsPrivate = (user['isPrivate'] as bool?) ?? false;
      if (accountIsPrivate && !_isPrivate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isPrivate = true);
        });
      }
    }

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
                    Expanded(
                      child: Text(
                        context.t.createPostNewPost,
                        style: const TextStyle(
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
                                  username.isEmpty
                                      ? context.t.createPostYou
                                      : username,
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
                            hintText: context.t.createPostCaptionHint,
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
                              context.t.createPostPlace,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PostFormField(
                              controller: _placeNameCtrl,
                              hintText: context.t.createPostPlaceNameHint,
                              icon: Icons.place_outlined,
                              onChanged: (_) {
                                if (_placeFromCurrentLocation) {
                                  setState(
                                      () => _placeFromCurrentLocation = false);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            CityPickerField(
                              value: _placeCityCtrl.text,
                              hintText: context.t.createPostCityHint,
                              icon: Icons.location_city_outlined,
                              onChanged: (city) {
                                setState(() {
                                  _placeCityCtrl.text = city;
                                  if (_placeFromCurrentLocation) {
                                    _placeFromCurrentLocation = false;
                                  }
                                });
                              },
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
                                    icon: const Icon(
                                        Icons.my_location_rounded),
                                    label: Text(
                                      context.t.createPostUseCurrentLocation,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _locateTypedPlaceOnMap,
                                    icon: const Icon(Icons.map_outlined),
                                    label: Text(
                                      context.t.createPostLocateOnMap,
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

                      // VIDEO GRID
                      if (_pickedVideos.isNotEmpty)
                        _VideoGrid(
                          files: _pickedVideos,
                          onRemove: _removeVideo,
                        ),
                      if (_pickedVideos.isNotEmpty) const SizedBox(height: 16),

                      // ACTION TILES
                      _ActionTile(
                        icon: Icons.photo_library_outlined,
                        label: context.t.createPostPhotoFromGallery,
                        onTap: _pickImages,
                      ),
                      const SizedBox(height: 8),
                      _ActionTile(
                        icon: Icons.camera_alt_outlined,
                        label: context.t.createPostTakeAPhoto,
                        onTap: _pickFromCamera,
                      ),
                      const SizedBox(height: 8),
                      _ActionTile(
                        icon: Icons.video_library_outlined,
                        label: context.t.createPostVideoFromGallery,
                        onTap: _pickVideoFromGallery,
                      ),
                      const SizedBox(height: 8),
                      _ActionTile(
                        icon: Icons.videocam_outlined,
                        label: context.t.createPostRecordAVideo,
                        onTap: _pickVideoFromCamera,
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 13,
                              color: context.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                context.t.createPostVideoSizeLimit,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                        _bottomTab(context.t.post, 0, true),
                        _bottomTab(context.t.story, 1, false),
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
            : Text(
                context.t.post,
                style: const TextStyle(
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
              isPrivate
                  ? context.t.createPostFollowersOnly
                  : context.t.createPostPublic,
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

class _VideoGrid extends StatelessWidget {
  final List<File> files;
  final ValueChanged<int> onRemove;
  const _VideoGrid({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 16 / 11,
      ),
      itemCount: files.length,
      itemBuilder: (_, i) => _VideoThumb(
        file: files[i],
        onRemove: () => onRemove(i),
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final File file;
  final VoidCallback onRemove;
  const _VideoThumb({required this.file, required this.onRemove});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..setVolume(0)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: Colors.black,
              child: ready
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    )
                  : const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 42,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: widget.onRemove,
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
