import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'add_to_story_screen.dart';
import 'create_post_screen.dart';
import 'live_screen.dart';

// ─────────────────────────────────────────────
// 📌 SECTION: Camera / Story Screen
// ─────────────────────────────────────────────
class CameraStoryScreen extends StatefulWidget {
  const CameraStoryScreen({super.key});

  @override
  State<CameraStoryScreen> createState() => _CameraStoryScreenState();
}

class _CameraStoryScreenState extends State<CameraStoryScreen> {
  int _bottomTab = 1; // 0=Post, 1=Story, 2=Live
  int _flashMode = 2; // 0=Off, 1=On, 2=Auto
  bool _isExpanded = false;

  // ── Tab selection & navigation ──────────────
  void _onTabSelected(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CreatePostScreen()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LiveScreen()),
        );
        break;
      default:
        setState(() => _bottomTab = index);
    }
  }

  // ── Build ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2B2D30),
      body: SafeArea(
        child: Stack(
          children: [
            // 📌 SECTION: Top Bar
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _flashMode = (_flashMode + 1) % 3),
                    child: Icon(
                      _flashMode == 0
                          ? Icons.flash_off
                          : _flashMode == 1
                              ? Icons.flash_on
                              : Icons.flash_auto,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),

            // ── Divider below top bar ───────────
            const Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Divider(
                color: Colors.white54,
                thickness: 0.5,
              ),
            ),

            // 📌 SECTION: Left Side Menu
            Positioned(
              top: 120,
              left: 16,
              child: _buildLeftMenu(),
            ),

            // 📌 SECTION: Bottom Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Gallery thumbnail → navigates to AddToStoryScreen
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddToStoryScreen(),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/img/1.png',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              frameBuilder: (_, child, frame, __) =>
                                  frame != null
                                      ? child
                                      : const SizedBox(width: 44, height: 44),
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(width: 44, height: 44),
                            ),
                          ),
                        ),

                        // Shutter button
                        const _ShutterButton(),

                        // Flip camera
                        SvgPicture.asset(
                          'assets/icons/reverse.svg',
                          colorFilter: const ColorFilter.mode(
                              Colors.white, BlendMode.srcIn),
                          width: 28,
                          height: 28,
                        ),
                      ],
                    ),
                  ),

                  // ── Tabs ─────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTab("Post", 0),
                        const SizedBox(width: 24),
                        _buildTab("Story", 1),
                        const SizedBox(width: 24),
                        _buildTab("Live", 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Left menu ───────────────────────────────
  Widget _buildLeftMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIcon(iconPath: 'assets/icons/Aa.svg', label: "Create", index: 0),
        _buildIcon(
            iconPath: 'assets/icons/infinity.svg',
            label: "Boomerang",
            index: 1),
        _buildIcon(
            iconPath: 'assets/icons/layout.svg', label: "Layout", index: 2),
        _buildCollapseArrow(label: "Close"),
      ],
    );
  }

  Widget _buildIcon({
    required String iconPath,
    required String label,
    required int index,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SvgPicture.asset(
            iconPath,
            colorFilter:
                const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            width: index == 0 ? 13 : 22,
            height: index == 0 ? 13 : 22,
          ),
          const SizedBox(width: 8),
          if (_isExpanded)
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCollapseArrow({required String label}) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SvgPicture.asset(
              _isExpanded
                  ? 'assets/icons/arrow-up.svg'
                  : 'assets/icons/arrow-down.svg',
              colorFilter:
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              width: 22,
              height: 22,
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Tab button ──────────────────────────────
  Widget _buildTab(String text, int index) {
    final bool isActive = _bottomTab == index;
    return GestureDetector(
      onTap: () => _onTabSelected(index),
      child: Text(
        text,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white54,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          fontSize: 15,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Shutter Button
// ─────────────────────────────────────────────
class _ShutterButton extends StatefulWidget {
  const _ShutterButton();

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: _pressed ? 72 : 76,
        height: _pressed ? 72 : 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _pressed ? 56 : 60,
            height: _pressed ? 56 : 60,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}