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

  final List<_StoryTextOverlay> _overlays = [];
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
    final result = await Navigator.of(context).push<_StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => const _TextComposerScreen(),
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

  Future<void> _editOverlay(_StoryTextOverlay overlay) async {
    final result = await Navigator.of(context).push<_StoryTextOverlay>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        pageBuilder: (_, __, ___) => _TextComposerScreen(initial: overlay),
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
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
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
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
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
                            child: Image.file(widget.file, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      for (final overlay in _overlays)
                        _OverlayWidget(
                          key: ValueKey(overlay.id),
                          overlay: overlay,
                          canvasSize: size,
                          isActive: overlay.id == _activeOverlayId,
                          onActivate: () => setState(
                              () => _activeOverlayId = overlay.id),
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
                                _isOverTrash(globalPos, size);
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

// ── Overlay model ────────────────────────────────────────────────

enum _StoryFontStyle { classic, bold, italic, mono }

enum _StoryBackgroundStyle { none, filled, translucent }

class _StoryTextOverlay {
  final String id;
  final String text;
  // 0..1 canvas-relative coords so the overlay stays in the same logical
  // spot if the canvas is ever resized (orientation change) before publish.
  final Offset position;
  final Color color;
  final _StoryFontStyle fontStyle;
  final _StoryBackgroundStyle backgroundStyle;
  final TextAlign alignment;
  final double fontSize;
  final double scale;
  final double rotation; // radians

  const _StoryTextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    required this.fontStyle,
    required this.backgroundStyle,
    required this.alignment,
    this.fontSize = 28,
    this.scale = 1,
    this.rotation = 0,
  });

  _StoryTextOverlay copyWith({
    String? id,
    String? text,
    Offset? position,
    Color? color,
    _StoryFontStyle? fontStyle,
    _StoryBackgroundStyle? backgroundStyle,
    TextAlign? alignment,
    double? fontSize,
    double? scale,
    double? rotation,
  }) {
    return _StoryTextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontStyle: fontStyle ?? this.fontStyle,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      alignment: alignment ?? this.alignment,
      fontSize: fontSize ?? this.fontSize,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}

TextStyle _textStyleFor(_StoryTextOverlay o) {
  final base = TextStyle(
    color: o.color,
    fontSize: o.fontSize,
    height: 1.15,
    shadows: const [
      Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0, 2)),
    ],
  );
  switch (o.fontStyle) {
    case _StoryFontStyle.classic:
      return base.copyWith(fontWeight: FontWeight.w600);
    case _StoryFontStyle.bold:
      return base.copyWith(
          fontWeight: FontWeight.w900, letterSpacing: 0.5);
    case _StoryFontStyle.italic:
      return base.copyWith(
          fontWeight: FontWeight.w500, fontStyle: FontStyle.italic);
    case _StoryFontStyle.mono:
      return base.copyWith(
          fontWeight: FontWeight.w600, fontFamily: 'monospace');
  }
}

BoxDecoration? _backgroundDecorationFor(_StoryTextOverlay o) {
  switch (o.backgroundStyle) {
    case _StoryBackgroundStyle.none:
      return null;
    case _StoryBackgroundStyle.filled:
      return BoxDecoration(
        color: o.color,
        borderRadius: BorderRadius.circular(8),
      );
    case _StoryBackgroundStyle.translucent:
      return BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      );
  }
}

/// Text inside a "filled" background needs to flip to a contrasting color
/// or it becomes invisible (e.g., white text on a white pill).
/// Selection styling for a placed overlay — a soft outer halo (boxShadow)
/// instead of a border, so the rendered shape is byte-for-byte identical
/// whether the overlay is selected or not. Matches the composer preview.
BoxDecoration? _selectionDecoration(_StoryTextOverlay o, bool isActive) {
  final base = _backgroundDecorationFor(o);
  if (!isActive) return base;
  final halo = [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.85),
      blurRadius: 0,
      spreadRadius: 1,
    ),
  ];
  if (base == null) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: halo,
    );
  }
  return base.copyWith(boxShadow: halo);
}

Color _displayColorFor(_StoryTextOverlay o) {
  if (o.backgroundStyle != _StoryBackgroundStyle.filled) return o.color;
  // YIQ-style luminance check to pick black vs white for the foreground.
  final l = (o.color.r * 255 * 299 +
          o.color.g * 255 * 587 +
          o.color.b * 255 * 114) /
      1000;
  return l > 150 ? Colors.black : Colors.white;
}

// ── Overlay widget (placed on the canvas) ────────────────────────

class _OverlayWidget extends StatefulWidget {
  final _StoryTextOverlay overlay;
  final Size canvasSize;
  final bool isActive;
  final VoidCallback onActivate;
  final ValueChanged<_StoryTextOverlay> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _OverlayWidget({
    super.key,
    required this.overlay,
    required this.canvasSize,
    required this.isActive,
    required this.onActivate,
    required this.onChanged,
    required this.onEdit,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<_OverlayWidget> {
  // Snapshot of overlay state at gesture start so deltas apply on top of
  // the original values rather than compounding each frame.
  late _StoryTextOverlay _start;
  late Offset _startFocalPx;

  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    final centerX = o.position.dx * widget.canvasSize.width;
    final centerY = o.position.dy * widget.canvasSize.height;

    final displayColor = _displayColorFor(o);
    final textStyle = _textStyleFor(o).copyWith(color: displayColor);

    return Positioned(
      left: centerX - widget.canvasSize.width / 2,
      top: centerY - widget.canvasSize.height / 2,
      width: widget.canvasSize.width,
      height: widget.canvasSize.height,
      child: IgnorePointer(
        // The hit area is the inner text box; the surrounding Positioned is
        // just a layout anchor so Transform.rotate is centered on the text.
        ignoring: false,
        child: Center(
          child: Transform.rotate(
            angle: o.rotation,
            child: Transform.scale(
              scale: o.scale,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onActivate,
                onDoubleTap: widget.onEdit,
                onScaleStart: (details) {
                  widget.onDragStart();
                  _start = widget.overlay;
                  _startFocalPx = details.focalPoint;
                },
                onScaleUpdate: (details) {
                  // Convert the focal-point delta into canvas-relative units
                  // so the move integrates with the 0..1 position scheme.
                  final dxPx = details.focalPoint.dx - _startFocalPx.dx;
                  final dyPx = details.focalPoint.dy - _startFocalPx.dy;
                  final nextPos = Offset(
                    (_start.position.dx +
                            dxPx / widget.canvasSize.width)
                        .clamp(0.05, 0.95),
                    (_start.position.dy +
                            dyPx / widget.canvasSize.height)
                        .clamp(0.05, 0.95),
                  );
                  final nextScale =
                      (_start.scale * details.scale).clamp(0.4, 5.0);
                  final nextRotation =
                      _start.rotation + details.rotation;
                  widget.onChanged(_start.copyWith(
                    position: nextPos,
                    scale: nextScale,
                    rotation: nextRotation,
                  ));
                  widget.onDragUpdate(details.focalPoint);
                },
                onScaleEnd: (_) => widget.onDragEnd(),
                child: Container(
                  // Constrain to most of the canvas width before rotation
                  // so very long text wraps instead of overflowing.
                  constraints: BoxConstraints(
                    maxWidth: widget.canvasSize.width * 0.85,
                  ),
                  padding: o.backgroundStyle == _StoryBackgroundStyle.none
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                  // Active selection is shown via a soft outer halo
                  // (boxShadow) rather than a border, so the rendered
                  // shape is identical whether selected or not — and
                  // therefore identical to the composer preview.
                  decoration: _selectionDecoration(o, widget.isActive),
                  child: Text(
                    o.text,
                    textAlign: o.alignment,
                    style: textStyle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Full-screen text composer ────────────────────────────────────

class _TextComposerScreen extends StatefulWidget {
  final _StoryTextOverlay? initial;
  const _TextComposerScreen({this.initial});

  @override
  State<_TextComposerScreen> createState() => _TextComposerScreenState();
}

class _TextComposerScreenState extends State<_TextComposerScreen> {
  static const _palette = <Color>[
    Colors.white,
    Colors.black,
    Color(0xFFB05ECC),
    Color(0xFFEF476F),
    Color(0xFFFFD166),
    Color(0xFF06D6A0),
    Color(0xFF118AB2),
    Color(0xFFFF7B00),
    Color(0xFF7209B7),
    Color(0xFF80FFDB),
  ];

  late final TextEditingController _controller;
  late Color _color;
  late _StoryFontStyle _fontStyle;
  late _StoryBackgroundStyle _backgroundStyle;
  late TextAlign _alignment;
  double _fontSize = 32;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _controller = TextEditingController(text: i?.text ?? '');
    _color = i?.color ?? Colors.white;
    _fontStyle = i?.fontStyle ?? _StoryFontStyle.classic;
    _backgroundStyle = i?.backgroundStyle ?? _StoryBackgroundStyle.none;
    _alignment = i?.alignment ?? TextAlign.center;
    _fontSize = i?.fontSize ?? 32;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cycleFont() {
    setState(() {
      const values = _StoryFontStyle.values;
      _fontStyle =
          values[(values.indexOf(_fontStyle) + 1) % values.length];
    });
  }

  void _cycleBackground() {
    setState(() {
      const values = _StoryBackgroundStyle.values;
      _backgroundStyle =
          values[(values.indexOf(_backgroundStyle) + 1) % values.length];
    });
  }

  void _cycleAlignment() {
    setState(() {
      const values = [TextAlign.left, TextAlign.center, TextAlign.right];
      _alignment = values[(values.indexOf(_alignment) + 1) % values.length];
    });
  }

  IconData get _backgroundIcon {
    switch (_backgroundStyle) {
      case _StoryBackgroundStyle.none:
        return Icons.format_color_text;
      case _StoryBackgroundStyle.filled:
        return Icons.format_color_fill;
      case _StoryBackgroundStyle.translucent:
        return Icons.opacity;
    }
  }

  IconData get _alignmentIcon {
    switch (_alignment) {
      case TextAlign.left:
        return Icons.format_align_left;
      case TextAlign.right:
        return Icons.format_align_right;
      default:
        return Icons.format_align_center;
    }
  }

  void _commit() {
    // Drop focus first so the keyboard's dismiss animation runs in parallel
    // with the pop — otherwise the canvas appears to "wait" for the
    // keyboard to close before the placed overlay shows the new shape.
    FocusManager.instance.primaryFocus?.unfocus();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      _StoryTextOverlay(
        id: widget.initial?.id ?? 'pending',
        text: text,
        position: widget.initial?.position ?? const Offset(0.5, 0.5),
        color: _color,
        fontStyle: _fontStyle,
        backgroundStyle: _backgroundStyle,
        alignment: _alignment,
        fontSize: _fontSize,
        scale: widget.initial?.scale ?? 1,
        rotation: widget.initial?.rotation ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _StoryTextOverlay(
      id: 'preview',
      text: _controller.text.isEmpty ? 'Aa' : _controller.text,
      position: const Offset(0.5, 0.5),
      color: _color,
      fontStyle: _fontStyle,
      backgroundStyle: _backgroundStyle,
      alignment: _alignment,
      fontSize: _fontSize,
    );
    final displayColor = _displayColorFor(preview);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _commit,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      _ComposerChip(
                        icon: _alignmentIcon,
                        onTap: _cycleAlignment,
                      ),
                      const SizedBox(width: 8),
                      _ComposerChip(
                        icon: _backgroundIcon,
                        onTap: _cycleBackground,
                      ),
                      const SizedBox(width: 8),
                      _FontStyleChip(
                        fontStyle: _fontStyle,
                        onTap: _cycleFont,
                      ),
                      const Spacer(),
                      _ComposerChip(
                        icon: Icons.check,
                        accent: true,
                        onTap: _commit,
                      ),
                    ],
                  ),
                ),
                // Vertical size slider on the left edge, mirroring IG.
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.35),
                              thumbColor: Colors.white,
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8),
                            ),
                            child: Slider(
                              min: 16,
                              max: 72,
                              value: _fontSize,
                              onChanged: (v) =>
                                  setState(() => _fontSize = v),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            // Swallow taps on the TextField area so tapping
                            // the field itself doesn't trigger the commit
                            // gesture on the surrounding GestureDetector.
                            onTap: () {},
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.85,
                              ),
                              child: Container(
                                padding: _backgroundStyle ==
                                        _StoryBackgroundStyle.none
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                decoration: _backgroundDecorationFor(preview),
                                child: TextField(
                                  controller: _controller,
                                  autofocus: true,
                                  maxLines: null,
                                  textAlign: _alignment,
                                  cursorColor: displayColor,
                                  style: _textStyleFor(preview)
                                      .copyWith(color: displayColor),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    hintText: '',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Color palette — horizontal scroll, tap to apply.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + MediaQuery.of(context).viewInsets.bottom * 0,
                  ),
                  child: GestureDetector(
                    onTap: () {},
                    child: SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _palette.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final c = _palette[i];
                          final selected = c.toARGB32() == _color.toARGB32();
                          return GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: Container(
                              width: selected ? 32 : 28,
                              height: selected ? 32 : 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white24,
                                  width: selected ? 3 : 2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;
  const _ComposerChip({
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent
              ? const Color(0xFFB05ECC)
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _FontStyleChip extends StatelessWidget {
  final _StoryFontStyle fontStyle;
  final VoidCallback onTap;
  const _FontStyleChip({required this.fontStyle, required this.onTap});

  String get _label {
    switch (fontStyle) {
      case _StoryFontStyle.classic:
        return 'Aa';
      case _StoryFontStyle.bold:
        return 'Aa';
      case _StoryFontStyle.italic:
        return 'Aa';
      case _StoryFontStyle.mono:
        return 'Aa';
    }
  }

  TextStyle get _style {
    switch (fontStyle) {
      case _StoryFontStyle.classic:
        return const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16);
      case _StoryFontStyle.bold:
        return const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16);
      case _StoryFontStyle.italic:
        return const TextStyle(
            color: Colors.white,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            fontSize: 16);
      case _StoryFontStyle.mono:
        return const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            fontSize: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(child: Text(_label, style: _style)),
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
