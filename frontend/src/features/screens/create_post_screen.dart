import 'package:coil/src/features/screens/camera_story_screen.dart';
import 'package:flutter/material.dart';
import 'live_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  int selectedIndex = 0;
  int bottomTab = 0;

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  final List<String> images = [
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset.clamp(0.0, 220.0);
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
    final double fullHeight = MediaQuery.of(context).size.width - 24;
    final double previewHeight = fullHeight * (1 - _scrollOffset / 220);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        // 📌 FIX: expand forces Stack to fill Scaffold body exactly
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Column(
                children: [
                  // ── Dark header ───────────────
                  Container(
                    color: const Color(0xFF2B2D30),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 16),
                              const Text(
                                "Create New Post",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                "Next",
                                style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Collapsing preview image
                        ClipRect(
                          child: SizedBox(
                            height: previewHeight,
                            width: double.infinity,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  images[selectedIndex],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Album row
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text("Recent",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14)),
                                  SizedBox(width: 4),
                                  Icon(Icons.keyboard_arrow_down,
                                      color: Colors.white, size: 18),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(Icons.crop_square,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 4),
                                  Text("Select",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Photo grid ────────────────
                  Expanded(
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                          bottom: 80, left: 6, right: 6, top: 6),
                      itemCount: images.length + 1,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: const Color(0xFF3A3B3F),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 28),
                            ),
                          );
                        }

                        final index = i - 1;
                        final isSelected = selectedIndex == index;

                        return GestureDetector(
                          onTap: () =>
                              setState(() => selectedIndex = index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(images[index],
                                    fit: BoxFit.cover),

                                if (isSelected)
                                  Container(
                                      color: Colors.black
                                          .withValues(alpha: 0.35)),

                                if (isSelected)
                                  const Positioned(
                                    top: 6,
                                    right: 6,
                                    child: CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.purpleAccent,
                                      child: Icon(Icons.check,
                                          size: 13, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),   // end SafeArea

            // ── Floating pill tab bar ─────────
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
                      _buildTab("Post", 0),
                      _buildTab("Story", 1),
                      _buildTab("Live", 2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        );
  }

  Widget _buildTab(String text, int index) {
    final isActive = bottomTab == index;

    return GestureDetector(
      onTap: () {
        setState(() => bottomTab = index);
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