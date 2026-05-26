import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../services/story_service.dart';
import '../../utils/app_feedback.dart';
import '../widgets/story_text_overlay.dart';

/// Full-screen composer for text-only stories. The user picks a
/// background gradient and a text color, types their content, and
/// publishes — no image or video required. The resulting story is
/// rendered by [StoryViewerScreen] using the same `backgroundColor`/
/// `textColor` values stored on the doc.
class TextStoryComposerScreen extends StatefulWidget {
  const TextStoryComposerScreen({super.key});

  @override
  State<TextStoryComposerScreen> createState() =>
      _TextStoryComposerScreenState();
}

class _TextStoryComposerScreenState extends State<TextStoryComposerScreen> {
  // Each preset is a pair of (background color, suggested text color). The
  // text color is just the starting point — the user can override from the
  // small palette below.
  static const List<_BgPreset> _presets = [
    _BgPreset(Color(0xFFB05ECC), Colors.white),
    _BgPreset(Color(0xFF1E1F22), Colors.white),
    _BgPreset(Color(0xFFEF476F), Colors.white),
    _BgPreset(Color(0xFFFFD166), Colors.black),
    _BgPreset(Color(0xFF06D6A0), Colors.black),
    _BgPreset(Color(0xFF118AB2), Colors.white),
    _BgPreset(Color(0xFF7209B7), Colors.white),
    _BgPreset(Color(0xFF073B4C), Colors.white),
    _BgPreset(Colors.white, Colors.black),
  ];

  static const List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFFFD166),
    Color(0xFFFF7B00),
    Color(0xFFEF476F),
    Color(0xFF06D6A0),
  ];

  // Available text-shape options, cycled with a single header button.
  // 'brush' is the hand-painted ink-blot look — the text sits on top of
  // a slightly imperfect black blob, drawn by [BrushBackground].
  static const List<String> _borderStyles = [
    'none',
    'rounded',
    'pill',
    'outline',
    'box',
    'brush',
  ];

  final TextEditingController _controller = TextEditingController();
  int _bgIndex = 0;
  late Color _textColor = _presets[0].textColor;
  int _borderIndex = 0;
  bool _uploading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pickBackground(int index) {
    setState(() {
      _bgIndex = index;
      _textColor = _presets[index].textColor;
    });
  }

  Future<void> _publish() async {
    if (_uploading) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final bg = _presets[_bgIndex].background;
      await StoryService().createStory(
        imageUrl: '',
        textContent: text,
        backgroundColor: bg.toARGB32(),
        textColor: _textColor.toARGB32(),
        textBorderStyle: _borderStyles[_borderIndex],
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      AppFeedback.showSuccessOn(messenger, context.t.storyPublishedUploaded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, context.t.storyFailedPublish(e));
    }
  }

  void _cycleBorderStyle() {
    setState(() {
      _borderIndex = (_borderIndex + 1) % _borderStyles.length;
    });
  }

  IconData get _borderIcon {
    switch (_borderStyles[_borderIndex]) {
      case 'rounded':
        return Icons.crop_square_rounded;
      case 'pill':
        return Icons.crop_din_rounded;
      case 'outline':
        return Icons.border_outer;
      case 'box':
        return Icons.square_outlined;
      case 'brush':
        return Icons.brush;
      case 'none':
      default:
        return Icons.format_clear;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _presets[_bgIndex].background;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _CircleIcon(
                      icon: Icons.close,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _CircleIcon(
                      icon: _borderIcon,
                      onTap: _cycleBorderStyle,
                    ),
                    const SizedBox(width: 10),
                    _CircleIcon(
                      icon: Icons.format_color_text,
                      onTap: () => _cycleTextColor(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: _StyledTextWrapper(
                      style: _borderStyles[_borderIndex],
                      bg: bg,
                      textColor: _textColor,
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textAlign: TextAlign.center,
                        cursorColor: _textColor,
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                        // Explicitly disable the global
                        // InputDecorationTheme fill — without this the
                        // theme's `filled: true` + light-grey fillColor
                        // shows up as a milky white rectangle behind the
                        // text, defeating the user-picked shape style.
                        decoration: InputDecoration(
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          isCollapsed: true,
                          hintText: context.t.textStoryHint,
                          hintStyle: TextStyle(
                            color: _textColor.withValues(alpha: 0.55),
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final p = _presets[i];
                      final selected = i == _bgIndex;
                      return GestureDetector(
                        onTap: () => _pickBackground(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: selected ? 44 : 36,
                          height: selected ? 44 : 36,
                          decoration: BoxDecoration(
                            color: p.background,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                              width: selected ? 3 : 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                child: Row(
                  children: [
                    _PillButton(
                      label: context.t.cancel,
                      filled: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: _controller.text.trim().isEmpty ? 0.5 : 1.0,
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
              if (_uploading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleTextColor() {
    final idx = _textColors.indexWhere(
      (c) => c.toARGB32() == _textColor.toARGB32(),
    );
    final next = _textColors[(idx + 1) % _textColors.length];
    setState(() => _textColor = next);
  }
}

class _BgPreset {
  final Color background;
  final Color textColor;
  const _BgPreset(this.background, this.textColor);
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
          color: Colors.black.withValues(alpha: 0.35),
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

/// Wraps a text widget in one of the available [textBorderStyle] shapes.
/// Reused by both the composer preview and the story viewer renderer so
/// what the user sees while composing matches the published result.
class _StyledTextWrapper extends StatelessWidget {
  final String style;
  final Color bg;
  final Color textColor;
  final Widget child;

  const _StyledTextWrapper({
    required this.style,
    required this.bg,
    required this.textColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StoryTextShape(
      style: style,
      bg: bg,
      textColor: textColor,
      child: child,
    );
  }
}

/// Public wrapper so the story viewer can render the same shape without
/// duplicating the styling logic.
class StoryTextShape extends StatelessWidget {
  final String style;
  final Color bg;
  final Color textColor;
  final Widget child;

  const StoryTextShape({
    super.key,
    required this.style,
    required this.bg,
    required this.textColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 'rounded':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        );
      case 'pill':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: const StadiumBorder(),
          ),
          child: child,
        );
      case 'outline':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: textColor.withValues(alpha: 0.85),
              width: 2,
            ),
          ),
          child: child,
        );
      case 'box':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: textColor,
          ),
          // Flip the inner text to the background color so the filled box
          // stays readable. We rebuild the text widget by walking the
          // child's default style — done at the call site by passing a
          // child that already uses the bg color. Without that the user
          // would have to manually invert; see the composer where the
          // 'box' style is paired with the bg color for visibility.
          child: DefaultTextStyle.merge(
            style: TextStyle(color: bg),
            child: child,
          ),
        );
      case 'brush':
        // Hand-painted ink blob behind the text (see [BrushBlobPainter]).
        // Force the inner text to white so it reads against the black
        // ink — the user's text color stays applied to non-brush shapes.
        return BrushBackground(
          color: Colors.black,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: child,
          ),
        );
      case 'none':
      default:
        return child;
    }
  }
}
