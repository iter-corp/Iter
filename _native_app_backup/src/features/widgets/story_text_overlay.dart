import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

// ─────────────────────────────────────────────
// Public overlay model + composer + placed-overlay widget, shared
// between [StoryPreviewScreen] (image stories) and
// [VideoStoryPreviewScreen] (video stories). Persists to Firestore as
// the `overlays` field on a story doc; the viewer reads it back to
// render the same text on top of the playing image / video.
// ─────────────────────────────────────────────

enum StoryFontStyle { classic, bold, italic, mono }

/// Which color the composer's palette is editing.
enum _ColorTarget { text, shape }

/// Visual treatment behind the text overlay.
///   • [none]        — no background, just text + drop shadow.
///   • [filled]      — solid rounded pill in the user's color.
///   • [translucent] — semi-transparent black rounded card.
///   • [brush]       — hand-painted ink-blot stroke (see [BrushBlobPainter]),
///                     gives the "highlighter" / "tape" look users see in
///                     IG/TikTok stories.
enum StoryBackgroundStyle { none, filled, translucent, brush }

class StoryTextOverlay {
  final String id;
  final String text;
  // 0..1 canvas-relative coords so the overlay survives an orientation
  // change or a difference between compose canvas and viewer canvas.
  final Offset position;
  final Color color;
  /// Color of the shape/background (filled pill, translucent card, brush
  /// blob). Independent from [color] (the text color) so the user can style
  /// text and shape separately. Defaults to black for back-compat with
  /// overlays saved before this field existed.
  final Color backgroundColor;
  final StoryFontStyle fontStyle;
  final StoryBackgroundStyle backgroundStyle;
  final TextAlign alignment;
  final double fontSize;
  final double scale;
  final double rotation; // radians

  const StoryTextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    this.backgroundColor = Colors.black,
    required this.fontStyle,
    required this.backgroundStyle,
    required this.alignment,
    this.fontSize = 28,
    this.scale = 1,
    this.rotation = 0,
  });

  StoryTextOverlay copyWith({
    String? id,
    String? text,
    Offset? position,
    Color? color,
    Color? backgroundColor,
    StoryFontStyle? fontStyle,
    StoryBackgroundStyle? backgroundStyle,
    TextAlign? alignment,
    double? fontSize,
    double? scale,
    double? rotation,
  }) {
    return StoryTextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontStyle: fontStyle ?? this.fontStyle,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      alignment: alignment ?? this.alignment,
      fontSize: fontSize ?? this.fontSize,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  /// JSON representation used for the Firestore `overlays` array.
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'x': position.dx,
        'y': position.dy,
        'color': color.toARGB32(),
        'backgroundColor': backgroundColor.toARGB32(),
        'fontStyle': fontStyle.name,
        'backgroundStyle': backgroundStyle.name,
        'alignment': alignment.name,
        'fontSize': fontSize,
        'scale': scale,
        'rotation': rotation,
      };

  factory StoryTextOverlay.fromJson(Map<String, dynamic> j) {
    StoryFontStyle parseFont(String? s) {
      for (final v in StoryFontStyle.values) {
        if (v.name == s) return v;
      }
      return StoryFontStyle.classic;
    }

    StoryBackgroundStyle parseBg(String? s) {
      for (final v in StoryBackgroundStyle.values) {
        if (v.name == s) return v;
      }
      return StoryBackgroundStyle.none;
    }

    TextAlign parseAlign(String? s) {
      switch (s) {
        case 'left':
          return TextAlign.left;
        case 'right':
          return TextAlign.right;
        default:
          return TextAlign.center;
      }
    }

    return StoryTextOverlay(
      id: (j['id'] as String?) ?? '',
      text: (j['text'] as String?) ?? '',
      position: Offset(
        (j['x'] as num?)?.toDouble() ?? 0.5,
        (j['y'] as num?)?.toDouble() ?? 0.5,
      ),
      color: Color((j['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
      // Back-compat: overlays saved before separate shape color default to
      // black (the old hardcoded background).
      backgroundColor:
          Color((j['backgroundColor'] as num?)?.toInt() ?? 0xFF000000),
      fontStyle: parseFont(j['fontStyle'] as String?),
      backgroundStyle: parseBg(j['backgroundStyle'] as String?),
      alignment: parseAlign(j['alignment'] as String?),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 28,
      scale: (j['scale'] as num?)?.toDouble() ?? 1,
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Pick a text direction from the content's first strong character so
/// Kurdish / Arabic story text lays out right-to-left (correct caret
/// position, word order and punctuation) regardless of the app's ambient
/// locale. Falls back to LTR for Latin / neutral text.
TextDirection storyTextDirection(String text) {
  for (final rune in text.runes) {
    // Arabic (0x0600–0x06FF), Arabic Supplement / Extended-A, and the
    // Arabic Presentation Forms cover Kurdish (Sorani) and Arabic script.
    if ((rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    // First strong Latin letter → LTR.
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

TextStyle textStyleForOverlay(StoryTextOverlay o) {
  final base = TextStyle(
    color: o.color,
    fontSize: o.fontSize,
    height: 1.15,
    shadows: const [
      Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0, 2)),
    ],
  );
  switch (o.fontStyle) {
    case StoryFontStyle.classic:
      return base.copyWith(fontWeight: FontWeight.w600);
    case StoryFontStyle.bold:
      return base.copyWith(
          fontWeight: FontWeight.w900, letterSpacing: 0.5);
    case StoryFontStyle.italic:
      return base.copyWith(
          fontWeight: FontWeight.w500, fontStyle: FontStyle.italic);
    case StoryFontStyle.mono:
      return base.copyWith(
          fontWeight: FontWeight.w600, fontFamily: 'monospace');
  }
}

BoxDecoration? overlayBackgroundFor(StoryTextOverlay o) {
  switch (o.backgroundStyle) {
    case StoryBackgroundStyle.none:
      return null;
    case StoryBackgroundStyle.filled:
      return BoxDecoration(
        color: o.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      );
    case StoryBackgroundStyle.translucent:
      return BoxDecoration(
        color: o.backgroundColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      );
    case StoryBackgroundStyle.brush:
      // Painted by [BrushBlobPainter] (a CustomPainter), not via a
      // BoxDecoration — uneven blob shape needs Path drawing. Returning
      // null here means call sites must wrap the text in
      // [wrapWithBrushIfNeeded] / paint a [BrushBlobPainter] underneath.
      return null;
  }
}

BoxDecoration? overlaySelectionDecoration(StoryTextOverlay o, bool isActive) {
  // No visible selection chrome. A freshly placed/edited overlay is always
  // the active one, so any selection box (white halo or border) would show
  // up immediately and read as a background the editor never displayed —
  // exactly the "editing shows X, output shows Y" mismatch users hit.
  // Selection still works functionally (drag / pinch / double-tap-to-edit);
  // it just isn't painted. The overlay renders identically in the editor
  // preview, the placed widget, and the final viewer.
  return overlayBackgroundFor(o);
}

/// Text color actually used when rendering an overlay.
///
/// The text color is now fully user-controlled (separate from the shape
/// color), so we simply honor [o.color] for every background style. The
/// editor preview, the placed widget and the viewer all use this same
/// function, so what the user sees while picking is what gets published.
Color overlayDisplayColor(StoryTextOverlay o) => o.color;

// ─────────────────────────────────────────────
// Placed overlay widget — pan / pinch / rotate / double-tap-to-edit.
// ─────────────────────────────────────────────

class StoryOverlayWidget extends StatefulWidget {
  final StoryTextOverlay overlay;
  final Size canvasSize;
  final bool isActive;
  final VoidCallback onActivate;
  final ValueChanged<StoryTextOverlay> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const StoryOverlayWidget({
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
  State<StoryOverlayWidget> createState() => _StoryOverlayWidgetState();
}

class _StoryOverlayWidgetState extends State<StoryOverlayWidget> {
  late StoryTextOverlay _start;
  late Offset _startFocalPx;

  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    final centerX = o.position.dx * widget.canvasSize.width;
    final centerY = o.position.dy * widget.canvasSize.height;

    final displayColor = overlayDisplayColor(o);
    final textStyle = textStyleForOverlay(o).copyWith(color: displayColor);

    return Positioned(
      left: centerX - widget.canvasSize.width / 2,
      top: centerY - widget.canvasSize.height / 2,
      width: widget.canvasSize.width,
      height: widget.canvasSize.height,
      child: IgnorePointer(
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
                child: _wrapWithBackground(
                  overlay: o,
                  isActive: widget.isActive,
                  canvasSize: widget.canvasSize,
                  text: Text(
                    o.text,
                    textAlign: o.alignment,
                    textDirection: storyTextDirection(o.text),
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

/// Shared wrapper used by both [StoryOverlayWidget] (interactive editor)
/// and [StoryOverlayStatic] (read-only viewer). Picks the right
/// background treatment based on [overlay.backgroundStyle], including
/// the painted [BrushBackground] for brush style.
Widget _wrapWithBackground({
  required StoryTextOverlay overlay,
  required bool isActive,
  required Size canvasSize,
  required Widget text,
}) {
  final maxWidth = canvasSize.width * 0.85;
  if (overlay.backgroundStyle == StoryBackgroundStyle.brush) {
    // The brush blob itself is the visible treatment — no extra selection
    // chrome, which previously read as a stray white box around it.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: BrushBackground(color: overlay.backgroundColor, child: text),
    );
  }
  return Container(
    constraints: BoxConstraints(maxWidth: maxWidth),
    padding: overlay.backgroundStyle == StoryBackgroundStyle.none
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: overlaySelectionDecoration(overlay, isActive),
    child: text,
  );
}

// ─────────────────────────────────────────────
// Static (non-interactive) rendering used by the story viewer to draw
// overlays on top of the playing media. Same look as the placed widget
// minus the gesture machinery.
// ─────────────────────────────────────────────

class StoryOverlayStatic extends StatelessWidget {
  final StoryTextOverlay overlay;
  final Size canvasSize;

  const StoryOverlayStatic({
    super.key,
    required this.overlay,
    required this.canvasSize,
  });

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final centerX = o.position.dx * canvasSize.width;
    final centerY = o.position.dy * canvasSize.height;
    final displayColor = overlayDisplayColor(o);
    final textStyle = textStyleForOverlay(o).copyWith(color: displayColor);

    return Positioned(
      left: centerX - canvasSize.width / 2,
      top: centerY - canvasSize.height / 2,
      width: canvasSize.width,
      height: canvasSize.height,
      child: IgnorePointer(
        child: Center(
          child: Transform.rotate(
            angle: o.rotation,
            child: Transform.scale(
              scale: o.scale,
              child: _wrapWithBackground(
                overlay: o,
                isActive: false,
                canvasSize: canvasSize,
                text: Text(
                  o.text,
                  textAlign: o.alignment,
                  textDirection: storyTextDirection(o.text),
                  style: textStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Full-screen text composer — returns a new/edited StoryTextOverlay.
// ─────────────────────────────────────────────

class StoryTextComposerScreen extends StatefulWidget {
  final StoryTextOverlay? initial;
  const StoryTextComposerScreen({super.key, this.initial});

  @override
  State<StoryTextComposerScreen> createState() =>
      _StoryTextComposerScreenState();
}

class _StoryTextComposerScreenState extends State<StoryTextComposerScreen> {
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
  late Color _backgroundColor;
  late StoryFontStyle _fontStyle;
  late StoryBackgroundStyle _backgroundStyle;
  late TextAlign _alignment;
  double _fontSize = 32;

  // Which color the bottom palette is currently editing: the text or the
  // shape/background. Lets the user style both, separately, from one strip.
  _ColorTarget _colorTarget = _ColorTarget.text;

  // Pinch resizes the whole overlay via [_scale] (a Transform on the box),
  // NOT the font size. The placed/static widget applies the same
  // `Transform.scale(scale)` with the same fixed `fontSize`, so the editor
  // preview and the published overlay are pixel-identical — no reflow, no
  // "looked one size while editing, another after publishing" mismatch.
  double _scale = 1;
  double? _scaleAtPinchStart;

  static const double _minScale = 0.4;
  static const double _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _controller = TextEditingController(text: i?.text ?? '');
    _color = i?.color ?? Colors.white;
    _backgroundColor = i?.backgroundColor ?? Colors.black;
    _fontStyle = i?.fontStyle ?? StoryFontStyle.classic;
    // `filled` is now a first-class style with its own color, so reopening an
    // overlay that used it no longer needs migrating away.
    _backgroundStyle = i?.backgroundStyle ?? StoryBackgroundStyle.none;
    _alignment = i?.alignment ?? TextAlign.center;
    _fontSize = i?.fontSize ?? 32;
    _scale = i?.scale ?? 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cycleFont() {
    setState(() {
      const values = StoryFontStyle.values;
      _fontStyle =
          values[(values.indexOf(_fontStyle) + 1) % values.length];
    });
  }

  // Font size is changed in steps via the A−/A+ control. Pinch separately
  // controls the whole-box [_scale]; the two are independent so the user can
  // pick a base text size AND scale the box.
  static const double _minFontSize = 16;
  static const double _maxFontSize = 72;
  static const double _fontSizeStep = 4;

  void _decreaseFontSize() {
    setState(() {
      _fontSize = (_fontSize - _fontSizeStep).clamp(_minFontSize, _maxFontSize);
    });
  }

  void _increaseFontSize() {
    setState(() {
      _fontSize = (_fontSize + _fontSizeStep).clamp(_minFontSize, _maxFontSize);
    });
  }

  void _cycleBackground() {
    setState(() {
      // Now that the shape has its own user-chosen color (independent of the
      // text color), `filled` is back in the cycle — it draws a solid pill in
      // the shape color. Full range: none / filled / translucent / brush.
      const values = StoryBackgroundStyle.values;
      final i = values.indexOf(_backgroundStyle);
      _backgroundStyle = values[(i + 1) % values.length];
      // Jumping onto a style that paints a shape? Make sure the palette is
      // editing the shape color so the next tap is intuitive.
      if (_backgroundStyle == StoryBackgroundStyle.none) {
        _colorTarget = _ColorTarget.text;
      }
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
      case StoryBackgroundStyle.none:
        return Icons.format_color_text;
      case StoryBackgroundStyle.filled:
        return Icons.format_color_fill;
      case StoryBackgroundStyle.translucent:
        return Icons.opacity;
      case StoryBackgroundStyle.brush:
        return Icons.brush;
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
    FocusManager.instance.primaryFocus?.unfocus();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      StoryTextOverlay(
        id: widget.initial?.id ?? 'pending',
        text: text,
        position: widget.initial?.position ?? const Offset(0.5, 0.5),
        color: _color,
        backgroundColor: _backgroundColor,
        fontStyle: _fontStyle,
        backgroundStyle: _backgroundStyle,
        alignment: _alignment,
        fontSize: _fontSize,
        // Pinch in the composer adjusts the box scale (not font size), and
        // the placed/static overlay applies this same scale, so what the
        // user sized in the editor is exactly what publishes.
        scale: _scale,
        rotation: widget.initial?.rotation ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = StoryTextOverlay(
      id: 'preview',
      text: _controller.text.isEmpty ? 'Aa' : _controller.text,
      position: const Offset(0.5, 0.5),
      color: _color,
      backgroundColor: _backgroundColor,
      fontStyle: _fontStyle,
      backgroundStyle: _backgroundStyle,
      alignment: _alignment,
      fontSize: _fontSize,
    );
    final displayColor = overlayDisplayColor(preview);
    // Whether the palette is allowed to edit the shape color: only when the
    // current style actually paints a shape.
    final canEditShape = _backgroundStyle != StoryBackgroundStyle.none;
    final editingShape = canEditShape && _colorTarget == _ColorTarget.shape;
    final selectedColor = editingShape ? _backgroundColor : _color;

    return Scaffold(
      // Transparent so the real story media (the composer is pushed as a
      // non-opaque route over the preview screen) shows through. The route's
      // own barrierColor provides the dim. Previously this Scaffold added a
      // second black@0.65 layer on top of the barrier — together ~85% black —
      // which made the `translucent` box look near-solid-black while editing,
      // even though on the bright video it renders as a light grey. Dropping
      // the extra layer makes the editor preview match the committed result.
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
                    const SizedBox(width: 8),
                    // Text-size stepper — changes the font size, independent
                    // of the pinch-to-resize box scale.
                    _FontSizeStepper(
                      onDecrease: _decreaseFontSize,
                      onIncrease: _increaseFontSize,
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
              Expanded(
                // Pinch anywhere on the editing canvas to resize the text —
                // replaces the old vertical font-size slider. `onTap` here is
                // a no-op that just absorbs taps in the empty area so they
                // don't bubble up to the screen-level `_commit` handler; taps
                // on the TextField itself still place the cursor.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onScaleStart: (_) => _scaleAtPinchStart = _scale,
                  onScaleUpdate: (details) {
                    final base = _scaleAtPinchStart ?? _scale;
                    final next =
                        (base * details.scale).clamp(_minScale, _maxScale);
                    if (next != _scale) {
                      setState(() => _scale = next);
                    }
                  },
                  onScaleEnd: (_) => _scaleAtPinchStart = null,
                  child: Center(
                    // Same Transform.scale the placed/static overlay applies,
                    // so the editor preview matches the published size exactly.
                    child: Transform.scale(
                      scale: _scale,
                      child: GestureDetector(
                          onTap: () {},
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            child: _backgroundStyle ==
                                    StoryBackgroundStyle.brush
                                ? BrushBackground(
                                    color: _backgroundColor,
                                    child: TextField(
                                      controller: _controller,
                                      autofocus: true,
                                      maxLines: null,
                                      textAlign: _alignment,
                                      textDirection:
                                          storyTextDirection(_controller.text),
                                      cursorColor: displayColor,
                                      style: textStyleForOverlay(preview)
                                          .copyWith(color: displayColor),
                                      // `filled: false` overrides the global
                                      // InputDecorationTheme which sets a
                                      // light-grey fill — that fill was
                                      // showing as a square behind the
                                      // story text while editing.
                                      decoration: const InputDecoration(
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isCollapsed: true,
                                        hintText: '',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  )
                                : Container(
                                    padding: _backgroundStyle ==
                                            StoryBackgroundStyle.none
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                    decoration: overlayBackgroundFor(preview),
                                    child: TextField(
                                      controller: _controller,
                                      autofocus: true,
                                      maxLines: null,
                                      textAlign: _alignment,
                                      textDirection:
                                          storyTextDirection(_controller.text),
                                      cursorColor: displayColor,
                                      style: textStyleForOverlay(preview)
                                          .copyWith(color: displayColor),
                                      decoration: const InputDecoration(
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: GestureDetector(
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Text / Shape toggle — picks which color the palette
                      // below edits. The "Shape" tab only appears when the
                      // current background style actually paints a shape.
                      if (canEditShape)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ColorTargetTab(
                                label: context.t.storyTextColorTabText,
                                selected: _colorTarget == _ColorTarget.text,
                                swatch: _color,
                                onTap: () => setState(
                                    () => _colorTarget = _ColorTarget.text),
                              ),
                              const SizedBox(width: 8),
                              _ColorTargetTab(
                                label: context.t.storyTextColorTabShape,
                                selected: _colorTarget == _ColorTarget.shape,
                                swatch: _backgroundColor,
                                onTap: () => setState(
                                    () => _colorTarget = _ColorTarget.shape),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _palette.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final c = _palette[i];
                            final selected =
                                c.toARGB32() == selectedColor.toARGB32();
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (editingShape) {
                                  _backgroundColor = c;
                                } else {
                                  _color = c;
                                }
                              }),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab of the Text / Shape color toggle. Shows a small swatch of the
/// color it currently controls plus a label, and highlights when selected.
class _ColorTargetTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Color swatch;
  final VoidCallback onTap;

  const _ColorTargetTab({
    required this.label,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 1),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A−/A+ stepper for the text font size. Two tappable letters in a pill,
/// sized small/large to hint their effect.
class _FontSizeStepper extends StatelessWidget {
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _FontSizeStepper({
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onDecrease,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            color: Colors.white24,
          ),
          GestureDetector(
            onTap: onIncrease,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
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
  final StoryFontStyle fontStyle;
  final VoidCallback onTap;
  const _FontStyleChip({required this.fontStyle, required this.onTap});

  TextStyle get _style {
    switch (fontStyle) {
      case StoryFontStyle.classic:
        return const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16);
      case StoryFontStyle.bold:
        return const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16);
      case StoryFontStyle.italic:
        return const TextStyle(
            color: Colors.white,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            fontSize: 16);
      case StoryFontStyle.mono:
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
        child: Center(child: Text(context.t.storyTextFontSample, style: _style)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Brush-blob painter — draws a hand-painted ink stroke behind a child.
// Used for [StoryBackgroundStyle.brush] overlays and for the 'brush'
// text-border style on text-only stories.
//
// We avoid bundling a PNG so the shape scales with the text and works
// in any color. The look is reproduced by stacking a couple of slightly
// rotated, semi-transparent rounded rects with feathered shadows on top
// of each other — close enough to the ink-stroke look without going to
// full path geometry.
// ─────────────────────────────────────────────

class BrushBackground extends StatelessWidget {
  final Widget child;
  final Color color;
  const BrushBackground({
    super.key,
    required this.child,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BrushBlobPainter(color: color),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: child,
      ),
    );
  }
}

class BrushBlobPainter extends CustomPainter {
  final Color color;
  const BrushBlobPainter({this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layer 1: main blob — a tall rounded rect rotated a few degrees so
    // the corners don't look like a sticker. Soft drop-shadow gives the
    // edge a slightly diffused, paint-soaked feel.
    final main = Paint()..color = color;
    final shadow = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.04); // ~ -2.3°
    final centerRect = RRect.fromRectAndCorners(
      Rect.fromCenter(width: w * 0.98, height: h * 0.92, center: Offset.zero),
      topLeft: const Radius.elliptical(80, 50),
      topRight: const Radius.elliptical(50, 30),
      bottomLeft: const Radius.elliptical(40, 30),
      bottomRight: const Radius.elliptical(90, 60),
    );
    canvas.drawRRect(centerRect, shadow);
    canvas.drawRRect(centerRect, main);
    canvas.restore();

    // Layer 2: thinner overlay tilted the other way, slightly offset.
    // Builds the hand-painted "two-stroke" feel.
    canvas.save();
    canvas.translate(w / 2 + 6, h / 2 + 2);
    canvas.rotate(0.05);
    final topRect = RRect.fromRectAndCorners(
      Rect.fromCenter(width: w * 0.88, height: h * 0.55, center: Offset.zero),
      topLeft: const Radius.elliptical(60, 28),
      topRight: const Radius.elliptical(40, 20),
      bottomLeft: const Radius.elliptical(70, 32),
      bottomRight: const Radius.elliptical(50, 24),
    );
    canvas.drawRRect(topRect, main);
    canvas.restore();

    // Layer 3: tiny dot near the tail to suggest a paintbrush flick.
    canvas.drawCircle(
      Offset(w * 0.96, h * 0.78),
      h * 0.06,
      main,
    );
    canvas.drawCircle(
      Offset(w * 0.02, h * 0.32),
      h * 0.05,
      main,
    );
  }

  @override
  bool shouldRepaint(covariant BrushBlobPainter old) => old.color != color;
}
