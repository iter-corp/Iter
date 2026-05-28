import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../widgets/feature_disabled_view.dart';
import 'add_to_story_screen.dart';
import 'create_post_screen.dart';
import 'story_preview_screen.dart';
import 'text_story_composer_screen.dart';
import 'video_story_preview_screen.dart';

/// Distinguishes the two camera-setup failure modes so the message can be
/// localized at render time (the async setup code has no BuildContext).
enum _CameraInitError { noCameras, initFailed }

class CameraStoryScreen extends ConsumerStatefulWidget {
  const CameraStoryScreen({super.key});

  @override
  ConsumerState<CameraStoryScreen> createState() => _CameraStoryScreenState();
}

class _CameraStoryScreenState extends ConsumerState<CameraStoryScreen>
    with WidgetsBindingObserver {
  int _bottomTab = 1;
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = const [];
  int _activeCamera = 0;
  FlashMode _flashMode = FlashMode.auto;
  bool _uploading = false;
  bool _settingUpCamera = false;
  // Camera setup error kind, resolved to a localized message in
  // [_buildPreview] where a BuildContext is available. [_initErrorDetail]
  // holds the raw exception text for the "init failed" case.
  _CameraInitError? _initError;
  String _initErrorDetail = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Drop the reference BEFORE disposing so any rebuild while the
      // app is suspended sees `_controller == null` and renders the
      // spinner instead of CameraPreview(disposedController), which
      // trips a "used after dispose" assertion and paints a red error
      // screen for a frame.
      if (c != null) {
        _controller = null;
        _initFuture = null;
        if (mounted) setState(() {});
        // Fire-and-forget dispose; awaiting blocks the lifecycle
        // callback, which Android doesn't like.
        c.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null || _initError != null) _setupCamera();
    }
  }

  Future<List<CameraDescription>> _availableCamerasWithRetry() async {
    Object? lastError;
    var lastCameras = const <CameraDescription>[];
    const delays = [
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];

    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }
      if (!mounted) return const <CameraDescription>[];
      try {
        final cameras = await availableCameras();
        if (cameras.isNotEmpty) return cameras;
        lastCameras = cameras;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null && lastCameras.isEmpty) throw lastError;
    return lastCameras;
  }

  Future<void> _setupCamera({bool retryOnFailure = true}) async {
    if (_settingUpCamera) return;
    _settingUpCamera = true;
    var shouldRetrySetup = false;
    try {
      if (mounted) {
        setState(() {
          _initError = null;
          _initErrorDetail = '';
        });
      }

      _cameras = await _availableCamerasWithRetry();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _initError = _CameraInitError.noCameras);
        return;
      }
      if (_activeCamera >= _cameras.length) _activeCamera = 0;
      final desc = _cameras[_activeCamera];
      final c = CameraController(
        desc,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = c;
      _initFuture = c.initialize();
      try {
        await _initFuture;
      } catch (_) {
        _controller = null;
        _initFuture = null;
        if (mounted) setState(() {});
        await c.dispose();
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final retry = CameraController(
          desc,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        _controller = retry;
        _initFuture = retry.initialize();
        await _initFuture;
      }
      if (!mounted) return;
      await _controller?.setFlashMode(_flashMode);
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = _CameraInitError.initFailed;
          _initErrorDetail = '$e';
        });
      }
      shouldRetrySetup = retryOnFailure;
    } finally {
      _settingUpCamera = false;
    }

    if (shouldRetrySetup && mounted && _controller == null) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted && _controller == null) {
        await _setupCamera(retryOnFailure: false);
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _activeCamera = (_activeCamera + 1) % _cameras.length;
    // Clear the reference BEFORE awaiting dispose so any rebuild
    // happening during the await renders the spinner branch rather
    // than feeding a half-disposed controller to CameraPreview.
    final old = _controller;
    _controller = null;
    _initFuture = null;
    if (mounted) setState(() {});
    try {
      await old?.dispose();
    } catch (_) {}
    await _setupCamera();
  }

  Future<void> _cycleFlash() async {
    FlashMode next;
    switch (_flashMode) {
      case FlashMode.off:
        next = FlashMode.auto;
        break;
      case FlashMode.auto:
        next = FlashMode.always;
        break;
      case FlashMode.always:
      case FlashMode.torch:
        next = FlashMode.off;
        break;
    }
    _flashMode = next;
    try {
      await _controller?.setFlashMode(next);
    } catch (_) {}
    setState(() {});
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on;
    }
  }

  Future<void> _captureAndPreview() async {
    final c = _controller;
    if (_uploading || c == null || !c.value.isInitialized) return;
    setState(() => _uploading = true);
    try {
      final pic = await c.takePicture();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryPreviewScreen(file: File(pic.path)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.cameraCaptureFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openTextStory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TextStoryComposerScreen()),
    );
  }

  Future<void> _pickVideoFromGallery() async {
    if (_uploading) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
        // Stories are short — hint to the system picker (Android cropper) so
        // users don't pick a movie-length clip. Hard cap is enforced again
        // on the preview screen.
        maxDuration: const Duration(seconds: 30),
      );
      if (picked == null) return;
      // Verify the cached copy actually exists before pushing the
      // preview screen. On some Android devices the system picker
      // returns a path under cache/ that's evicted between pick and
      // read, so the preview screen would otherwise face a missing
      // file and fail to init.
      final file = File(picked.path);
      if (!await file.exists() || (await file.length()) == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.cameraCaptureFailed('empty file'))),
        );
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoStoryPreviewScreen(file: file),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.cameraCaptureFailed(e))),
      );
    }
  }

  void _onTabSelected(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CreatePostScreen()),
        );
        break;
      default:
        setState(() => _bottomTab = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storiesEnabled =
        ref.watch(adminConfigProvider).valueOrNull?.storiesEnabled ?? true;
    if (!storiesEnabled) {
      return FeatureDisabledView(
        feature: context.t.featureStories,
        icon: Icons.auto_stories_outlined,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),

            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: Icons.text_fields_rounded,
                    onTap: _openTextStory,
                  ),
                  const SizedBox(width: 10),
                  _CircleButton(
                    icon: Icons.videocam_outlined,
                    onTap: _pickVideoFromGallery,
                  ),
                  const SizedBox(width: 10),
                  _CircleButton(
                    icon: _flashIcon,
                    onTap: _cycleFlash,
                  ),
                ],
              ),
            ),

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
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddToStoryScreen(),
                            ),
                          ),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.photo_library_outlined,
                                color: Colors.white),
                          ),
                        ),
                        _ShutterButton(
                          uploading: _uploading,
                          onTap: _captureAndPreview,
                        ),
                        GestureDetector(
                          onTap: _flipCamera,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                                Icons.cameraswitch_outlined,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTab(context.t.post, 0),
                        const SizedBox(width: 24),
                        _buildTab(context.t.story, 1),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_initError != null) {
      final message = _initError == _CameraInitError.noCameras
          ? context.t.cameraNoCamerasFound
          : context.t.cameraInitFailed(_initErrorDetail);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized || _initFuture == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        // `previewSize` is reported in the sensor's natural (landscape)
        // orientation, so in a portrait UI its width/height are
        // effectively swapped. Building a SizedBox straight from those
        // values and forcing BoxFit.cover stretched the image.
        //
        // Instead: take the camera's true aspect ratio (long/short),
        // and size an AspectRatio box so the *shorter* side fills the
        // screen — overflow on the longer side is cropped by the
        // surrounding ClipRect. This is the standard distortion-free
        // "camera cover" and matches the native camera app.
        final preview = c.value.previewSize;
        final shortSide = preview == null
            ? 9.0
            : (preview.width < preview.height
                ? preview.width
                : preview.height);
        final longSide = preview == null
            ? 16.0
            : (preview.width < preview.height
                ? preview.height
                : preview.width);

        return ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenW = constraints.maxWidth;
              final screenH = constraints.maxHeight;
              // Camera aspect ratio in the current (portrait) UI:
              // height is the long edge, width is the short edge.
              final cameraAspect = shortSide / longSide;
              final screenAspect = screenW / screenH;

              double previewW;
              double previewH;
              if (screenAspect > cameraAspect) {
                // Screen is wider than the camera frame → match width,
                // let height overflow (cropped top/bottom).
                previewW = screenW;
                previewH = screenW / cameraAspect;
              } else {
                // Screen is taller → match height, crop the sides.
                previewH = screenH;
                previewW = screenH * cameraAspect;
              }

              return OverflowBox(
                maxWidth: previewW,
                maxHeight: previewH,
                child: SizedBox(
                  width: previewW,
                  height: previewH,
                  child: CameraPreview(c),
                ),
              );
            },
          ),
        );
      },
    );
  }

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

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ShutterButton extends StatefulWidget {
  final bool uploading;
  final VoidCallback onTap;
  const _ShutterButton({required this.uploading, required this.onTap});

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.uploading) widget.onTap();
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
          ),
        ),
      ),
    );
  }
}
