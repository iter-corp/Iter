import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../services/story_service.dart';
import '../../utils/app_feedback.dart';
import '../widgets/story_text_overlay.dart'
    show StoryTextOverlay, StoryTextComposerScreen, StoryOverlayWidget;

class StoryPreviewScreen extends StatefulWidget {
  final File file;
  const StoryPreviewScreen({super.key, required this.file});

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  bool _uploading = false;

  // Pinch-to-zoom on the background image is the default gesture — no toggle
  // button, just put two fingers on the screen. Matches IG/FB story behavior.
  final TransformationController _zoomController = TransformationController();

  final List<StoryTextOverlay> _overlays = [];
  int _nextOverlayId = 0;
  String? _activeOverlayId;

  // Tracks whether an overlay is mid-drag so the bottom trash zone can fade
  // in, and whether the dragged overlay is currently hovering over the
  // trash zone (so it can pulse red before release).
  bool _draggingOverlay = false;
  bool _overTrash = false;

  // Rasterizes the final composition (background + overlays) into a PNG so
  // the upload includes the user's edits, not just the original photo.
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  Future<void> _addText() async {
    final result = await Navigator.of(context).push<StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => const StoryTextComposerScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (result == null) return;
    setState(() {
      final id = 'ov_${_nextOverlayId++}';
      // Place the new overlay roughly centered. The user can drag it
      // anywhere from there.
      _overlays.add(result.copyWith(id: id, position: const Offset(0.5, 0.5)));
      _activeOverlayId = id;
    });
  }

  Future<void> _editOverlay(StoryTextOverlay overlay) async {
    final result = await Navigator.of(context).push<StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => StoryTextComposerScreen(initial: overlay),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (result == null) return;
    setState(() {
      final idx = _overlays.indexWhere((o) => o.id == overlay.id);
      if (idx == -1) return;
      // Preserve placement (position, scale, rotation) — only the text
      // styling fields are replaced by the composer result.
      _overlays[idx] = overlay.copyWith(
        text: result.text,
        color: result.color,
        backgroundColor: result.backgroundColor,
        fontStyle: result.fontStyle,
        backgroundStyle: result.backgroundStyle,
        alignment: result.alignment,
        fontSize: result.fontSize,
        // Carry the composer's pinch-resized box scale back.
        scale: result.scale,
      );
    });
  }

  void _deleteOverlay(String id) {
    setState(() {
      _overlays.removeWhere((o) => o.id == id);
      if (_activeOverlayId == id) _activeOverlayId = null;
    });
  }

  /// Captures the on-screen canvas (image + overlays) into a PNG file so the
  /// uploaded story matches what the user edited. Falls back to the original
  /// photo if capture fails — better to publish the untouched image than to
  /// block the user from posting.
  Future<File> _renderCompositeOrFallback() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return widget.file;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return widget.file;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } catch (_) {
      return widget.file;
    }
  }

  Future<void> _publish() async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _activeOverlayId = null;
      _uploading = true;
    });
    try {
      // Render after the next frame so the deselected overlays (no border)
      // are what gets captured.
      await WidgetsBinding.instance.endOfFrame;
      final composite = await _renderCompositeOrFallback();
      final url = await StorageService().uploadStoryImage(composite);
      await StoryService().createStory(imageUrl: url);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      AppFeedback.showSuccessOn(messenger, context.t.storyPublishedUploaded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, context.t.storyFailedPublish(e));
    }
  }

  void _cancel() {
    if (_uploading) return;
    // Pop just this preview so the user lands back on the camera screen
    // that pushed it — they probably want to retake the shot, not jump
    // all the way out to home. (Previously this used popUntil(isFirst)
    // which kicked the user out of the add-story flow entirely.)
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
            // The capture target: background + all overlays. Anything outside
            // the RepaintBoundary (toolbar, action pills, trash zone) is
            // excluded from the published image.
            RepaintBoundary(
              key: _canvasKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      // InteractiveViewer gives free pinch-to-zoom + pan on
                      // the background out of the box. Tapping (single
                      // finger, no drag) deselects any active overlay.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_activeOverlayId != null) {
                            setState(() => _activeOverlayId = null);
                          }
                        },
                        child: InteractiveViewer(
                          transformationController: _zoomController,
                          minScale: 0.5,
                          maxScale: 4,
                          panEnabled: true,
                          child: Hero(
                            tag: 'story_preview_${widget.file.path}',
                            // Cover-fit so the composed/published image fills
                            // the screen with no edge gaps, matching the
                            // viewer. The RepaintBoundary rasterizes exactly
                            // what's shown here, so editor == output.
                            child: SizedBox.expand(
                              child: Image.file(widget.file, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                      for (final overlay in _overlays)
                        StoryOverlayWidget(
                          key: ValueKey(overlay.id),
                          overlay: overlay,
                          canvasSize: size,
                          isActive: overlay.id == _activeOverlayId,
                          onActivate: () =>
                              setState(() => _activeOverlayId = overlay.id),
                          onChanged: (updated) => setState(() {
                            final idx =
                                _overlays.indexWhere((o) => o.id == overlay.id);
                            if (idx != -1) _overlays[idx] = updated;
                          }),
                          onEdit: () => _editOverlay(overlay),
                          onDragStart: () => setState(() {
                            _draggingOverlay = true;
                            _activeOverlayId = overlay.id;
                          }),
                          onDragUpdate: (globalPos) {
                            final overTrash = _isOverTrash(globalPos, size);
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
            // Bottom gradient — hidden while dragging so the trash zone is
            // unambiguous.
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
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (!_draggingOverlay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: Row(
                        children: [
                          _PillButton(
                            label: context.t.cancel,
                            filled: false,
                            onTap: _cancel,
                          ),
                          const Spacer(),
                          _PillButton(
                            label: context.t.storyPublish,
                            icon: Icons.send_rounded,
                            filled: true,
                            onTap: _publish,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Drag-to-trash drop zone, IG-style: only visible while a text
            // overlay is being dragged. Overlay turns red while hovering.
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

  bool _isOverTrash(Offset globalPos, Size canvasSize) {
    // Trash circle sits ~bottom-center. Treat the bottom ~140px band as the
    // trash zone for forgiving hit-testing while dragging.
    const trashBandHeight = 140.0;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(globalPos);
    return local.dy > canvasSize.height - trashBandHeight &&
        (local.dx - canvasSize.width / 2).abs() < 80;
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
