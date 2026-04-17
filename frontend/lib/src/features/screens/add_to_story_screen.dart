import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import 'camera_story_screen.dart';
import 'create_post_screen.dart';
import 'live_screen.dart';
import 'story_preview_screen.dart';

class AddToStoryScreen extends ConsumerStatefulWidget {
  const AddToStoryScreen({super.key});

  @override
  ConsumerState<AddToStoryScreen> createState() => _AddToStoryScreenState();
}

class _AddToStoryScreenState extends ConsumerState<AddToStoryScreen> {
  int _bottomTab = 1;
  bool _loading = true;
  String? _permissionMessage;
  List<AssetEntity> _assets = const [];

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      if (mounted) {
        setState(() {
          _loading = false;
          _permissionMessage =
              'Photo permission denied. Enable it in settings to pick photos.';
        });
      }
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _assets = const [];
        });
      }
      return;
    }
    final recent = albums.first;
    final assets = await recent.getAssetListPaged(page: 0, size: 100);
    if (mounted) {
      setState(() {
        _assets = assets;
        _loading = false;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    _openPreview(File(picked.path));
  }

  Future<void> _pickAsset(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) return;
    _openPreview(file);
  }

  void _openPreview(File file) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryPreviewScreen(file: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  color: const Color(0xFF2B2D30),
                  padding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 26),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Add to story',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                    ],
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1F22),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTab('Post', 0),
                      _buildTab('Story', 1),
                      _buildTab('Live', 2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_permissionMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.76,
      ),
      itemCount: _assets.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return GestureDetector(
            onTap: _pickFromCamera,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: const Color(0xFF3A3C3F),
                child: const Center(
                  child: Icon(Icons.photo_camera_outlined,
                      color: Colors.white, size: 32),
                ),
              ),
            ),
          );
        }
        final asset = _assets[index - 1];
        return _AssetThumbCell(asset: asset, onTap: () => _pickAsset(asset));
      },
    );
  }

  Widget _buildTab(String text, int index) {
    final bool isActive = _bottomTab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _bottomTab = index);
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CameraStoryScreen()),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LiveScreen()),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _AssetThumbCell extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _AssetThumbCell({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: FutureBuilder(
          future: asset.thumbnailDataWithSize(
            const ThumbnailSize(256, 256),
          ),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) {
              return Container(color: const Color(0xFF3A3C3F));
            }
            return Image.memory(bytes, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}
