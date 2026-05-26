import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// Public overlay model + composer + placed-overlay widget, shared
// between [StoryPreviewScreen] (image stories) and
// [VideoStoryPreviewScreen] (video stories). Persists to Firestore as
// the `overlays` field on a story doc; the viewer reads it back to
// render the same text on top of the playing image / video.
// ─────────────────────────────────────────────

enum StoryFontStyle { classic, bold, italic, mono }

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
      fontStyle: parseFont(j['fontStyle'] as String?),
      backgroundStyle: parseBg(j['backgroundStyle'] as String?),
      alignment: parseAlign(j['alignment'] as String?),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 28,
      scale: (j['scale'] as num?)?.toDouble() ?? 1,
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
    );
  }
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
        color: o.color,
        borderRadius: BorderRadius.circular(8),
      );
    case StoryBackgroundStyle.translucent:
      return BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
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
  final base = overlayBackgroundFor(o);
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

/// Text inside a "filled" background flips to a contrasting color so
/// white-on-white (and black-on-black) never happens.
Color overlayDisplayColor(StoryTextOverlay o) {
  if (o.backgroundStyle != StoryBackgroundStyle.filled) return o.color;
  final l = (o.color.r * 255 * 299 +
          o.color.g * 255 * 587 +
          o.color.b * 255 * 114) /
      1000;
  return l > 150 ? Colors.black : Colors.white;
}

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
    final brush = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: BrushBackground(color: Colors.black, child: text),
    );
    if (!isActive) return brush;
    // Halo wraps the brush so the active-selection ring still appears.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.85),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: brush,
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
  late StoryFontStyle _fontStyle;
  late StoryBackgroundStyle _backgroundStyle;
  late TextAlign _alignment;
  double _fontSize = 32;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _controller = TextEditingController(text: i?.text ?? '');
    _color = i?.color ?? Colors.white;
    _fontStyle = i?.fontStyle ?? StoryFontStyle.classic;
    _backgroundStyle = i?.backgroundStyle ?? StoryBackgroundStyle.none;
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
      const values = StoryFontStyle.values;
      _fontStyle =
          values[(values.indexOf(_fontStyle) + 1) % values.length];
    });
  }

  void _cycleBackground() {
    setState(() {
      const values = StoryBackgroundStyle.values;
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
    final preview = StoryTextOverlay(
      id: 'preview',
      text: _controller.text.isEmpty ? 'Aa' : _controller.text,
      position: const Offset(0.5, 0.5),
      color: _color,
      fontStyle: _fontStyle,
      backgroundStyle: _backgroundStyle,
      alignment: _alignment,
      fontSize: _fontSize,
    );
    final displayColor = overlayDisplayColor(preview);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.65),
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
                          onTap: () {},
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            child: _backgroundStyle ==
                                    StoryBackgroundStyle.brush
                                ? BrushBackground(
                                    color: Colors.black,
                                    child: TextField(
                                      controller: _controller,
                                      autofocus: true,
                                      maxLines: null,
                                      textAlign: _alignment,
                                      cursorColor: Colors.white,
                                      style: textStyleForOverlay(preview)
                                          .copyWith(color: Colors.white),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
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
                                      cursorColor: displayColor,
                                      style: textStyleForOverlay(preview)
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
        child: Center(child: Text('Aa', style: _style)),
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
