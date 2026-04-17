import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/auth_providers.dart';
import '../../providers/live_providers.dart';
import 'camera_story_screen.dart';
import 'create_post_screen.dart';
import 'live_viewer_screen.dart';
import 'live_host_screen.dart';

// ─────────────────────────────────────────────
// 📌 SECTION: Live Screen
// ─────────────────────────────────────────────
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  // Live tab is always active (index 2)
  final int _activeTab = 2;

  void _showTitleSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LiveTitleSheet(
        onSubmit: (title) async {
          final uid = ref.read(authStateProvider).value?.uid;
          if (uid == null) return;
          final stream = await ref
              .read(liveServiceProvider)
              .startStream(hostUid: uid, title: title);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveHostScreen(stream: stream),
            ),
          );
        },
      ),
    );
  }

  void _onTabSelected(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CreatePostScreen()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CameraStoryScreen()),
        );
        break;
      case 2:
        // Already on Live — re-open title sheet
        _showTitleSheet();
        break;
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
            // 📌 SECTION: Top Bar (close only)
            Positioned(
              top: 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),

            // 📌 SECTION: Left Side Menu
            Positioned(
              top: 120,
              left: 16,
              child: _LiveLeftMenu(onOpenTitleSheet: _showTitleSheet),
            ),

            // 📌 SECTION: Active Streams
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              bottom: 160,
              child: _ActiveStreamsList(),
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
                        const SizedBox(width: 44), // balanced spacing
                        _LiveButton(onTap: _showTitleSheet),
                        const SizedBox(width: 28), // balanced spacing
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

  // ── Tab button ──────────────────────────────
  Widget _buildTab(String text, int index) {
    final bool isActive = _activeTab == index;
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
// 📌 SECTION: Live Left Menu
// ─────────────────────────────────────────────
class _LiveLeftMenu extends StatelessWidget {
  final VoidCallback onOpenTitleSheet;

  const _LiveLeftMenu({required this.onOpenTitleSheet});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        _TextToolIcon(onOpenTitleSheet: onOpenTitleSheet),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Text Tool Icon (T with underline)
// ─────────────────────────────────────────────
class _TextToolIcon extends StatelessWidget {
  final VoidCallback onOpenTitleSheet;

  const _TextToolIcon({required this.onOpenTitleSheet});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenTitleSheet,
      child: SvgPicture.asset(
        'assets/icons/title.svg',
        width: 30,
        height: 30,
        colorFilter: const ColorFilter.mode(
          Colors.white,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Live Broadcast Button
// ─────────────────────────────────────────────
class _LiveButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _LiveButton({this.onTap});

  @override
  State<_LiveButton> createState() => _LiveButtonState();
}

class _LiveButtonState extends State<_LiveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
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
            child: const Center(
              child: Icon(
                Icons.sensors, // concentric arc broadcast icon
                color: Color(0xFF2B2D30),
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveStreamsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamsAsync = ref.watch(activeStreamsProvider);

    return streamsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Live list unavailable',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ),
      data: (streams) {
        if (streams.isEmpty) {
          return Center(
            child: Text(
              'No one is live right now',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: streams.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final stream = streams[i];
            return Material(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveViewerScreen(stream: stream),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stream.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Host: ${stream.hostUid}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.remove_red_eye,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(width: 4),
                      Text(
                        '${stream.viewersCount}',
                        style: const TextStyle(color: Colors.white),
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
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Live Title Bottom Sheet
// ─────────────────────────────────────────────
class _LiveTitleSheet extends ConsumerStatefulWidget {
  final Future<void> Function(String title) onSubmit;

  const _LiveTitleSheet({required this.onSubmit});

  @override
  ConsumerState<_LiveTitleSheet> createState() => _LiveTitleSheetState();
}

class _LiveTitleSheetState extends ConsumerState<_LiveTitleSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag handle ──────────────────────
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Avatar + title input row ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // TODO: replace with real user avatar from backend
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/img/1.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0E0E0),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: false,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add a title...',
                    hintStyle:
                        TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Helper text ──────────────────────
          const Text(
            'your follower and anyone watching will see this title.',
            style: TextStyle(
              color: Color(0xFF999999),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),

          // ── Add Title button ─────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD044E8), Color(0xFF9B44E8)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: () async {
                  final title = _controller.text.trim();
                  if (title.isEmpty || _loading) return;
                  setState(() => _loading = true);
                  try {
                    await widget.onSubmit(title);
                    if (mounted) Navigator.pop(context);
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Go Live',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
