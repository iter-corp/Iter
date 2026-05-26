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

  // Trim window. The uploaded file isn't re-encoded — only `_trimStart`
  // and `_trimEnd` are persisted on the Story doc. The viewer clamps
  // playback to that window. The preview clamps it here too so the user
  // sees exactly what their followers will see.
  Duration _videoDuration = Duration.zero;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = Duration.zero;
  bool _seekingTrim = false;

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
      _videoDuration = c.value.duration;
      // Default trim window: full video if it fits, else clipped to the
      // 30s cap so the user lands on a usable selection they can refine
      // with the range slider instead of being told "video is too long".
      _trimStart = Duration.zero;
      _trimEnd = _videoDuration > _maxStoryDuration
          ? _maxStoryDuration
          : _videoDuration;
      // _tooLong only flips true if the user has somehow chosen a
      // window > 30s after the fact (shouldn't happen since the slider
      // is clamped, but keep the guard).
      _tooLong = (_trimEnd - _trimStart) > _maxStoryDuration;
      debugPrint('[VideoStorySetup] _videoDuration=$_videoDuration '
          'initial trim=$_trimStart..$_trimEnd _tooLong=$_tooLong');
      try {
        // Disable native looping — the position listener seeks back to
        // _trimStart manually when playback reaches _trimEnd.
        await c.setLooping(false);
      } catch (e) {
        debugPrint('[VideoStorySetup] setLooping failed: $e');
      }
      c.addListener(_onPositionTick);
      try {
        await c.seekTo(_trimStart);
        await c.play();
        debugPrint('[VideoStorySetup] play() OK');
      } catch (e) {
        debugPrint('[VideoStorySetup] play() failed: $e');
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
    _controller?.removeListener(_onPositionTick);
    _controller?.dispose();
    super.dispose();
  }

  /// Keeps preview playback inside the chosen trim window: whenever the
  /// position passes [_trimEnd], seek back to [_trimStart] and continue
  /// playing. Re-entrancy guard prevents stacked seeks while one is in
  /// flight.
  void _onPositionTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _seekingTrim) return;
    final pos = c.value.position;
    if (pos < _trimStart - const Duration(milliseconds: 250) ||
        pos >= _trimEnd) {
      _seekingTrim = true;
      c.seekTo(_trimStart).whenComplete(() {
        _seekingTrim = false;
        if (mounted) c.play();
      });
      return;
    }
    // Force a rebuild a few times a second so the trim slider can
    // render the playhead marker.
    if (mounted) {
      // Only setState when something visible would change to avoid
      // flooding the frame budget.
      setState(() {});
    }
  }

  void _onTrimChanged(RangeValues v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final totalMs = _videoDuration.inMilliseconds;
    if (totalMs == 0) return;
    var startMs = (v.start * totalMs).round();
    var endMs = (v.end * totalMs).round();
    // Cap the window at the 30s story limit.
    final maxMs = _maxStoryDuration.inMilliseconds;
    if (endMs - startMs > maxMs) {
      // Determine which handle moved by comparing to the existing
      // values; freeze the other so the window slides instead of
      // stretching past the cap.
      final movedStart =
          (startMs - _trimStart.inMilliseconds).abs() >
              (endMs - _trimEnd.inMilliseconds).abs();
      if (movedStart) {
        endMs = startMs + maxMs;
      } else {
        startMs = endMs - maxMs;
      }
    }
    setState(() {
      _trimStart = Duration(milliseconds: startMs.clamp(0, totalMs));
      _trimEnd = Duration(milliseconds: endMs.clamp(0, totalMs));
      _tooLong = (_trimEnd - _trimStart) > _maxStoryDuration;
    });
    // Snap the preview to the start handle so the user can see what
    // their first frame will be.
    _seekingTrim = true;
    c.seekTo(_trimStart).whenComplete(() {
      _seekingTrim = false;
      if (mounted) c.play();
    });
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
      // Persist the chosen trim window. The uploaded file is the full
      // video; the viewer clamps playback to this range so re-encoding
      // isn't needed.
      final hasTrim = _trimStart > Duration.zero ||
          _trimEnd < _videoDuration;
      final storyId = await StoryService().createStory(
        imageUrl: '',
        videoUrl: url,
        videoTrimStartMs: hasTrim ? _trimStart.inMilliseconds : null,
        videoTrimEndMs: hasTrim ? _trimEnd.inMilliseconds : null,
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
                  if (!_draggingOverlay &&
                      (_controller?.value.isInitialized ?? false) &&
                      _videoDuration.inMilliseconds > 0)
                    _TrimBar(
                      duration: _videoDuration,
                      start: _trimStart,
                      end: _trimEnd,
                      position: _controller?.value.position ?? Duration.zero,
                      maxWindow: _maxStoryDuration,
                      onChanged: _onTrimChanged,
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

/// Dual-handle trim bar shown above the publish row. Values are
/// expressed as fractions of the full video duration so the
/// [RangeSlider] (which clamps to 0..1) stays straightforward; the
/// parent converts to `Duration` when persisting.
class _TrimBar extends StatelessWidget {
  final Duration duration;
  final Duration start;
  final Duration end;
  final Duration position;
  final Duration maxWindow;
  final ValueChanged<RangeValues> onChanged;

  const _TrimBar({
    required this.duration,
    required this.start,
    required this.end,
    required this.position,
    required this.maxWindow,
    required this.onChanged,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();
    final startFrac = (start.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final endFrac = (end.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final selected = end - start;
    final maxedOut = selected >= maxWindow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.content_cut,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  _fmt(start),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  // Selected window length, e.g. "0:08 / 0:30 max".
                  '${_fmt(selected)} / ${_fmt(maxWindow)}',
                  style: TextStyle(
                    color: maxedOut
                        ? const Color(0xFFFFB454)
                        : Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _fmt(end),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFB05ECC),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                rangeThumbShape: const RoundRangeSliderThumbShape(
                    enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                trackHeight: 4,
              ),
              child: RangeSlider(
                min: 0,
                max: 1,
                values: RangeValues(startFrac, endFrac),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
