import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'create_post_screen.dart';
import 'camera_story_screen.dart';
import 'live_screen.dart';

// ─────────────────────────────────────────────
// 📌 SECTION: Add To Story / Gallery Picker Screen
// ─────────────────────────────────────────────
class AddToStoryScreen extends StatefulWidget {
  const AddToStoryScreen({super.key});

  @override
  State<AddToStoryScreen> createState() => _AddToStoryScreenState();
}

class _AddToStoryScreenState extends State<AddToStoryScreen> {
  int _bottomTab = 1;

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  // Top bar title section collapses over this many pixels of scroll
  static const double _collapseRange = 56.0;

  // 📌 SECTION: Mock gallery items
  // TODO: replace with real device gallery via photo_manager package
  static const List<_GalleryItem> _items = [
    _GalleryItem(isCamera: true),
    _GalleryItem(seed: '1'),
    _GalleryItem(seed: '2'),
    _GalleryItem(seed: '1'),
    _GalleryItem(seed: '2'),
    _GalleryItem(seed: '1', duration: '0:30'),
    _GalleryItem(seed: '2'),
    _GalleryItem(seed: '1'),
    _GalleryItem(seed: '2'),
    _GalleryItem(seed: '1'),
    _GalleryItem(seed: '2'),
    _GalleryItem(seed: '1'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset =
            _scrollController.offset.clamp(0.0, _collapseRange);
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 0.0 → fully visible, 1.0 → fully collapsed
    final double collapseProgress = _scrollOffset / _collapseRange;
    // Title bar height: 54px → 0px
    final double titleHeight = (54.0 * (1 - collapseProgress)).clamp(0.0, 54.0);
    // Title opacity: 1 → 0 (fades out in the first half of scroll)
    final double titleOpacity = (1 - collapseProgress * 2).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 📌 SECTION: Collapsing dark header
                Container(
                  color: const Color(0xFF2B2D30),
                  child: Column(
                    children: [
                      // ── Shrinking title bar ───────
                      ClipRect(
                        child: SizedBox(
                          height: titleHeight,
                          child: Opacity(
                            opacity: titleOpacity,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 26),
                                    ),
                                  ),
                                  const Text(
                                    'Add to story',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Album row always visible ──
                      _buildAlbumRow(),
                    ],
                  ),
                ),

                // 📌 SECTION: Photo grid
                Expanded(
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                      childAspectRatio: 0.76,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (_, index) =>
                        _GalleryCell(item: _items[index]),
                  ),
                ),
              ],
            ),

            // 📌 SECTION: Floating pill tab bar
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

  // ── Album row ────────────────────────────────
  Widget _buildAlbumRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Recent ▼
          const Row(
            children: [
              Text(
                'Recent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down,
                  color: Colors.white, size: 20),
            ],
          ),

          // Select pill
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/filled.svg',
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  width: 23,
                  height: 23,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Select',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pill tab button ──────────────────────────
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

// ─────────────────────────────────────────────
// 📌 SECTION: Gallery Item Model
// ─────────────────────────────────────────────
class _GalleryItem {
  final bool isCamera;
  final String? seed;
  final String? duration;

  const _GalleryItem({
    this.isCamera = false,
    this.seed,
    this.duration,
  });
}

// ─────────────────────────────────────────────
// 📌 SECTION: Gallery Cell Widget
// ─────────────────────────────────────────────
class _GalleryCell extends StatelessWidget {
  final _GalleryItem item;
  const _GalleryCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: item.isCamera ? _buildCameraCell() : _buildImageCell(),
    );
  }

  Widget _buildCameraCell() {
    return Container(
      color: const Color(0xFF3A3C3F),
      child: const Center(
        child: Icon(
          Icons.photo_camera_outlined,
          color: Colors.white60,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildImageCell() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/img/${item.seed}.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: const Color(0xFF3A3C3F)),
        ),

        // Duration badge
        if (item.duration != null)
          Positioned(
            bottom: 7,
            right: 7,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                item.duration!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}