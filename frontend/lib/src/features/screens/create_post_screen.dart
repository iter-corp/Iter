import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'camera_story_screen.dart';
import 'live_screen.dart';

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
  bool _isPrivate = false;
  bool _posting = false;
  double? _placeLat;
  double? _placeLng;
  bool _placeFromCurrentLocation = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _placeNameCtrl.dispose();
    _placeCityCtrl.dispose();
    super.dispose();
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                            _PostFormField(
                              controller: _placeCityCtrl,
                              hintText: 'City (optional)',
                              icon: Icons.location_city_outlined,
                              onChanged: (_) {
                                if (_placeFromCurrentLocation) {
                                  setState(
                                      () => _placeFromCurrentLocation = false);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _useCurrentLocationForPlace,
                                icon: const Icon(Icons.my_location_rounded),
                                label: const Text('Use current location'),
                              ),
                            ),
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
                        _bottomTab('Live', 2, false),
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
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveScreen()),
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
