import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../services/story_service.dart';
import '../../utils/app_feedback.dart';
import '../widgets/story_text_overlay.dart';

/// Preview + publish screen for a video story. Plays the picked video on
/// loop with a tap-to-mute affordance. Capped at 30 seconds — anything
/// longer is rejected up front so the upload doesn't spin for minutes
/// only to fail at playback time.
class VideoStoryPreviewScreen extends StatefulWidget {
  final File file;
  const VideoStoryPreviewScreen({super.key, required this.file});

  @override
  State<VideoStoryPreviewScreen> createState() =>
      _VideoStoryPreviewScreenState();
}

class _VideoStoryPreviewScreenState extends State<VideoStoryPreviewScreen>
    with WidgetsBindingObserver {
  static const Duration _maxStoryDuration = Duration(seconds: 30);

  VideoPlayerController? _controller;
  bool _uploading = false;
  bool _muted = false;
  String? _initError;
  bool _tooLong = false;

  // Draggable text overlays placed on top of the video. Same model the
  // image-story preview uses; persisted as Firestore docs on the story
  // so the viewer can re-render them.
  final List<StoryTextOverlay> _overlays = [];
  int _nextOverlayId = 0;
  String? _activeOverlayId;
  bool _draggingOverlay = false;
  bool _overTrash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause when backgrounded so the media player doesn't hold
    // resources unnecessarily; resume only if init actually succeeded
    // and the video isn't over the length cap.
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      if (!_tooLong) {
        try {
          c.play();
        } catch (_) {}
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      try {
        c.pause();
      } catch (_) {}
    }
  }

  Future<void> _setup() async {
    debugPrint('[VideoStorySetup] === _setup() called ===');
    debugPrint('[VideoStorySetup] file.path=${widget.file.path}');

    try {
      final exists = await widget.file.exists();
      debugPrint('[VideoStorySetup] file exists=$exists');
      if (!exists) {
        if (mounted) {
          setState(() => _initError = 'File not found: ${widget.file.path}');
        }
        return;
      }
      final size = await widget.file.length();
      debugPrint('[VideoStorySetup] file size=$size bytes');
      if (size == 0) {
        if (mounted) setState(() => _initError = 'Empty video file');
        return;
      }
    } catch (e, st) {
      debugPrint('[VideoStorySetup] file read failed: $e\n$st');
      if (mounted) setState(() => _initError = 'Cannot read file: $e');
      return;
    }

    VideoPlayerController? c;
    try {
      debugPrint('[VideoStorySetup] creating VideoPlayerController.file()');
      c = VideoPlayerController.file(widget.file);
      debugPrint('[VideoStorySetup] -> controller.initialize()');
      await c.initialize();
      debugPrint('[VideoStorySetup] <- initialize OK '
          'duration=${c.value.duration} aspect=${c.value.aspectRatio} '
          'size=${c.value.size}');
      if (!mounted) {
        debugPrint('[VideoStorySetup] not mounted post-init, disposing');
        await c.dispose();
        return;
      }
      _controller = c;
      _tooLong = c.value.duration > _maxStoryDuration;
      debugPrint('[VideoStorySetup] _tooLong=$_tooLong '
          'maxDuration=$_maxStoryDuration');
      try {
        await c.setLooping(true);
      } catch (e) {
        debugPrint('[VideoStorySetup] setLooping failed: $e');
      }
      if (!_tooLong) {
        try {
          await c.play();
          debugPrint('[VideoStorySetup] play() OK');
        } catch (e) {
          debugPrint('[VideoStorySetup] play() failed: $e');
        }
      }
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('[VideoStorySetup] !! init failed: $e\n$st');
      try {
        await c?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _initError = '$e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    final next = !_muted;
    await c.setVolume(next ? 0 : 1);
    setState(() => _muted = next);
  }

  Future<void> _publish() async {
    debugPrint('[VideoStoryPublish] === _publish() called ===');
    debugPrint('[VideoStoryPublish] state: _uploading=$_uploading '
        '_tooLong=$_tooLong file=${widget.file.path} '
        'overlays.count=${_overlays.length}');
    if (_uploading || _tooLong) {
      debugPrint('[VideoStoryPublish] ABORT: guard hit '
          '(_uploading=$_uploading _tooLong=$_tooLong)');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _activeOverlayId = null;
      _uploading = true;
    });

    // Pre-upload file sanity check so we don't blame the network for a
    // missing/empty file.
    try {
      final exists = await widget.file.exists();
      final size = exists ? await widget.file.length() : -1;
      debugPrint('[VideoStoryPublish] pre-upload file check: '
          'exists=$exists size=$size bytes path=${widget.file.path}');
      if (!exists) {
        throw Exception('Video file no longer exists at ${widget.file.path}');
      }
      if (size == 0) {
        throw Exception('Video file is empty');
      }
    } catch (e, st) {
      debugPrint('[VideoStoryPublish] pre-upload check failed: $e\n$st');
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, context.t.storyFailedPublish(e));
      return;
    }

    final uploadStart = DateTime.now();
    String url;
    try {
      debugPrint('[VideoStoryPublish] -> StorageService.uploadStoryVideo()');
      url = await StorageService().uploadStoryVideo(widget.file);
      final elapsed = DateTime.now().difference(uploadStart);
      debugPrint('[VideoStoryPublish] <- upload OK in ${elapsed.inMilliseconds}ms');
      debugPrint('[VideoStoryPublish] publicUrl=$url');
    } catch (e, st) {
      final elapsed = DateTime.now().difference(uploadStart);
      debugPrint('[VideoStoryPublish] !! upload FAILED after '
          '${elapsed.inMilliseconds}ms: $e');
      debugPrint('[VideoStoryPublish] upload stacktrace:\n$st');
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, context.t.storyFailedPublish(e));
      return;
    }

    final docStart = DateTime.now();
    try {
      debugPrint('[VideoStoryPublish] -> StoryService.createStory() '
          'videoUrl.len=${url.length} overlays=${_overlays.length}');
      final storyId = await StoryService().createStory(
        imageUrl: '',
        videoUrl: url,
        overlays: _overlays,
      );
      final elapsed = DateTime.now().difference(docStart);
      debugPrint('[VideoStoryPublish] <- createStory OK in '
          '${elapsed.inMilliseconds}ms storyId=$storyId');
    } catch (e, st) {
      final elapsed = DateTime.now().difference(docStart);
      debugPrint('[VideoStoryPublish] !! createStory FAILED after '
          '${elapsed.inMilliseconds}ms: $e');
      debugPrint('[VideoStoryPublish] createStory stacktrace:\n$st');
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, context.t.storyFailedPublish(e));
      return;
    }

    debugPrint('[VideoStoryPublish] === SUCCESS — popping to root ===');
    if (!mounted) {
      debugPrint('[VideoStoryPublish] not mounted after publish, skipping nav');
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    AppFeedback.showSuccessOn(messenger, context.t.storyPublishedUploaded);
  }

  Future<void> _addText() async {
    // Pause playback while editing so the moving video doesn't distract.
    await _controller?.pause();
    if (!mounted) return;
    final result = await Navigator.of(context).push<StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => const StoryTextComposerScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted && !_tooLong) {
      await _controller?.play();
    }
    if (result == null) return;
    setState(() {
      final id = 'ov_${_nextOverlayId++}';
      _overlays.add(result.copyWith(id: id, position: const Offset(0.5, 0.5)));
      _activeOverlayId = id;
    });
  }

  Future<void> _editOverlay(StoryTextOverlay overlay) async {
    await _controller?.pause();
    if (!mounted) return;
    final result = await Navigator.of(context).push<StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => StoryTextComposerScreen(initial: overlay),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted && !_tooLong) {
      await _controller?.play();
    }
    if (result == null) return;
    setState(() {
      final idx = _overlays.indexWhere((o) => o.id == overlay.id);
      if (idx == -1) return;
      _overlays[idx] = overlay.copyWith(
        text: result.text,
        color: result.color,
        fontStyle: result.fontStyle,
        backgroundStyle: result.backgroundStyle,
        alignment: result.alignment,
        fontSize: result.fontSize,
      );
    });
  }

  void _deleteOverlay(String id) {
    setState(() {
      _overlays.removeWhere((o) => o.id == id);
      if (_activeOverlayId == id) _activeOverlayId = null;
    });
  }

  bool _isOverTrash(Offset globalPos, Size canvasSize) {
    // Trash circle sits ~bottom-center. Treat the bottom ~140 px band
    // as the trash zone so the user doesn't have to be pixel-perfect.
    const trashBandHeight = 140.0;
    return globalPos.dy > canvasSize.height - trashBandHeight &&
        (globalPos.dx - canvasSize.width / 2).abs() < 80;
  }

  void _cancel() {
    if (_uploading) return;
    // Pop just this preview so the user returns to the camera screen.
    // Previously this used popUntil(isFirst) which dumped them back at
    // home and they'd have to re-enter the add-story flow from scratch.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video preview + placed text overlays sit inside one
            // LayoutBuilder so the overlays use the same canvas size
            // for their 0..1 coordinates as the editor will compute.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(),
                      // Tap empty area to deselect any active overlay.
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (_activeOverlayId != null) {
                              setState(() => _activeOverlayId = null);
                            }
                          },
                        ),
                      ),
                      for (final overlay in _overlays)
                        StoryOverlayWidget(
                          key: ValueKey(overlay.id),
                          overlay: overlay,
                          canvasSize: canvasSize,
                          isActive: overlay.id == _activeOverlayId,
                          onActivate: () =>
                              setState(() => _activeOverlayId = overlay.id),
                          onChanged: (updated) => setState(() {
                            final idx = _overlays
                                .indexWhere((o) => o.id == overlay.id);
                            if (idx != -1) _overlays[idx] = updated;
                          }),
                          onEdit: () => _editOverlay(overlay),
                          onDragStart: () => setState(() {
                            _draggingOverlay = true;
                            _activeOverlayId = overlay.id;
                          }),
                          onDragUpdate: (globalPos) {
                            final overTrash =
                                _isOverTrash(globalPos, canvasSize);
                            if (overTrash != _overTrash) {
                              setState(() => _overTrash = overTrash);
                            }
                          },
                          onDragEnd: () {
                            final shouldDelete = _overTrash;
                            setState(() {
                              _draggingOverlay = false;
                              _overTrash = false;
                            });
                            if (shouldDelete) _deleteOverlay(overlay.id);
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_draggingOverlay)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 220,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  if (!_draggingOverlay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(
                        children: [
                          _CircleIcon(icon: Icons.close, onTap: _cancel),
                          const Spacer(),
                          _CircleIcon(
                            icon: Icons.text_fields_rounded,
                            onTap: _addText,
                          ),
                          if (_controller?.value.isInitialized ?? false) ...[
                            const SizedBox(width: 10),
                            _CircleIcon(
                              icon:
                                  _muted ? Icons.volume_off : Icons.volume_up,
                              onTap: _toggleMute,
                            ),
                          ],
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (_tooLong)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          context.t.videoStoryTooLong,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  if (!_draggingOverlay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Row(
                        children: [
                          _PillButton(
                            label: context.t.cancel,
                            filled: false,
                            onTap: _cancel,
                          ),
                          const Spacer(),
                          Opacity(
                            opacity: _tooLong ? 0.5 : 1,
                            child: _PillButton(
                              label: context.t.storyPublish,
                              icon: Icons.send_rounded,
                              filled: true,
                              onTap: _publish,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Drag-to-trash drop zone — only visible while dragging a
            // placed overlay. The Aa / mute / publish chrome is hidden
            // during drag so this circle is unambiguous.
            if (_draggingOverlay)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _overTrash ? 80 : 64,
                      height: _overTrash ? 80 : 64,
                      decoration: BoxDecoration(
                        color: _overTrash
                            ? const Color(0xFFEF476F)
                            : Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.5),
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            if (_uploading)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _initError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: _toggleMute,
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFB05ECC) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: filled
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.5,
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: const Color(0xFFB05ECC).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
