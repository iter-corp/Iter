import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import 'camera_story_screen.dart';
import 'create_post_screen.dart';
import 'story_preview_screen.dart';

class AddToStoryScreen extends ConsumerStatefulWidget {
  const AddToStoryScreen({super.key});

  @override
  ConsumerState<AddToStoryScreen> createState() => _AddToStoryScreenState();
}

class _AddToStoryScreenState extends ConsumerState<AddToStoryScreen> {
  int _bottomTab = 1;
  bool _loading = true;
  bool _permissionDenied = false;
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _activeAlbum;
  List<AssetEntity> _assets = const [];
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 90;

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
          _permissionDenied = true;
        });
      }
      return;
    }

    // List every album the OS exposes (Recent, Camera, Screenshots, Downloads,
    // user-created folders, etc.) instead of only the "All" bucket. Lets the
    // user actually browse the full gallery.
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
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
    _albums = albums;
    _activeAlbum = albums.first;
    await _loadAssetsForActiveAlbum();
  }

  Future<void> _loadAssetsForActiveAlbum() async {
    final album = _activeAlbum;
    if (album == null) return;
    final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
    if (mounted) {
      setState(() {
        _assets = assets;
        _page = 0;
        _hasMore = assets.length == _pageSize;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final album = _activeAlbum;
    if (album == null) return;
    _loadingMore = true;
    final next =
        await album.getAssetListPaged(page: _page + 1, size: _pageSize);
    if (!mounted) {
      _loadingMore = false;
      return;
    }
    setState(() {
      _page += 1;
      _assets = [..._assets, ...next];
      _hasMore = next.length == _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _pickAlbum() async {
    final selected = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: const Color(0xFF1E1F22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlbumPickerSheet(
        albums: _albums,
        activeId: _activeAlbum?.id,
      ),
    );
    if (selected == null || selected.id == _activeAlbum?.id) return;
    setState(() {
      _activeAlbum = selected;
      _loading = true;
      _assets = const [];
    });
    await _loadAssetsForActiveAlbum();
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

  /// Opens the OS-native gallery picker as a fallback for users who'd rather
  /// browse photos in the system UI (Files app, Google Photos, etc.) than
  /// the in-app grid.
  Future<void> _pickFromSystemGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
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
      backgroundColor: context.cardBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  color: const Color(0xFF2B2D30),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _albums.isEmpty ? null : _pickAlbum,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _activeAlbum?.name.isNotEmpty == true
                                      ? _activeAlbum!.name
                                      : context.t.addToStory,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_albums.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white, size: 22),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _pickFromSystemGallery,
                        child: const Icon(Icons.folder_open_outlined,
                            color: Colors.white, size: 24),
                      ),
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
                      _buildTab(context.t.post, 0),
                      _buildTab(context.t.story, 1),
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
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 48, color: context.textSecondary),
              const SizedBox(height: 12),
              Text(context.t.storyPhotoPermissionDenied,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => PhotoManager.openSetting(),
                child: Text(context.t.storyOpenSettings),
              ),
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadMore();
        }
        return false;
      },
      child: GridView.builder(
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
      ),
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

class _AlbumPickerSheet extends StatelessWidget {
  final List<AssetPathEntity> albums;
  final String? activeId;
  const _AlbumPickerSheet({required this.albums, this.activeId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: albums.length,
                itemBuilder: (_, i) {
                  final a = albums[i];
                  final selected = a.id == activeId;
                  return ListTile(
                    leading: _AlbumCover(album: a),
                    title: Text(
                      a.name.isEmpty ? 'Album' : a.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                    onTap: () => Navigator.pop(context, a),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final AssetPathEntity album;
  const _AlbumCover({required this.album});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: FutureBuilder<List<AssetEntity>>(
          future: album.getAssetListPaged(page: 0, size: 1),
          builder: (context, snap) {
            final first =
                (snap.data ?? const []).isNotEmpty ? snap.data!.first : null;
            if (first == null) {
              return Container(color: const Color(0xFF3A3C3F));
            }
            return FutureBuilder(
              future: first.thumbnailDataWithSize(const ThumbnailSize(96, 96)),
              builder: (context, thumb) {
                final bytes = thumb.data;
                if (bytes == null) {
                  return Container(color: const Color(0xFF3A3C3F));
                }
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            );
          },
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
