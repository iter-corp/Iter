import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

// 📌 SECTION: Supported Languages
const List<String> _kLanguages = [
  'English(USA)',
  'Kurdish(Sorani)',
  'Arabic',
  'Persian',
  'Turkish',
];

class TranslateBody extends StatefulWidget {
  const TranslateBody({super.key});

  @override
  State<TranslateBody> createState() => _TranslateBodyState();
}

class _TranslateBodyState extends State<TranslateBody> {
  String _sourceLang = 'English(USA)';
  String _targetLang = 'Kurdish(Sorani)';
  final TextEditingController _inputController = TextEditingController();
  String _translatedText = '';
  bool _hasTranslation = false;
  bool _isRecording = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _swapLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
      final inputText = _inputController.text;
      _inputController.text = _translatedText;
      _translatedText = inputText;
    });
  }

  void _onTranslate() {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _hasTranslation = true;
      _translatedText =
          _targetLang == 'Kurdish(Sorani)' ? 'سڵاو' : input;
    });
  }

  void _copyToClipboard() {
    if (_translatedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _translatedText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EAF0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📌 Title
              const Text(
                'Translate',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),

              // 📌 Language Selector Row
              _LanguageSelectorRow(
                sourceLang: _sourceLang,
                targetLang: _targetLang,
                onSourceChanged: (val) => setState(() => _sourceLang = val),
                onTargetChanged: (val) => setState(() => _targetLang = val),
                onSwap: _swapLanguages,
              ),
              const SizedBox(height: 12),

              // 📌 Input Box
              _InputBox(
                controller: _inputController,
                isRecording: _isRecording,
                onMicTap: () =>
                    setState(() => _isRecording = !_isRecording),
              ),
              const SizedBox(height: 16),

              // 📌 Translate Button
              Center(
                child: SizedBox(
                  width: 200,
                  height: 35,
                  child: ElevatedButton(
                    onPressed: _onTranslate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCE5DE5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Translate',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 📌 Output Box
              _OutputBox(
                translatedText: _hasTranslation ? _translatedText : '',
                isRTL: _targetLang == 'Kurdish(Sorani)' ||
                    _targetLang == 'Arabic' ||
                    _targetLang == 'Persian',
                onBookmark: () {/* TODO */},
                onCopy: _copyToClipboard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 📌 SECTION: Language Selector Row
class _LanguageSelectorRow extends StatelessWidget {
  final String sourceLang;
  final String targetLang;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onSwap;

  const _LanguageSelectorRow({
    required this.sourceLang,
    required this.targetLang,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _LanguageDropdown(value: sourceLang, onChanged: onSourceChanged)),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onSwap,
          child: Container(
            width: 33,
            height: 33,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFCE5DE5),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: SvgPicture.asset(
              'assets/icons/swap.svg',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _LanguageDropdown(value: targetLang, onChanged: onTargetChanged)),
      ],
    );
  }
}

// 📌 SECTION: Language Dropdown
class _LanguageDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD7D7D7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 20),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
          items: _kLanguages
              .map((lang) => DropdownMenuItem(
                    value: lang,
                    child: Text(lang,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ))
              .toList(),
          onChanged: (val) { if (val != null) onChanged(val); },
        ),
      ),
    );
  }
}

// 📌 SECTION: Input Box
class _InputBox extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onMicTap;
  final bool isRecording;

  const _InputBox({
    required this.controller,
    required this.onMicTap,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Enter text...',
              hintStyle: TextStyle(fontSize: 15, color: Colors.grey.shade400),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold),
          ),

          // 🔹 Mic icon ↔ animated wave toggle
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: onMicTap,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: isRecording
                    ? const _WaveAnimation(key: ValueKey('wave'))
                    : SvgPicture.asset(
                        key: const ValueKey('mic'),
                        'assets/icons/voice.svg',
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 📌 SECTION: Animated Wave Widget
// 🔹 Uses ONE controller + per-bar Interval offsets — no Future.delayed, no dispose risk.
class _WaveAnimation extends StatefulWidget {
  const _WaveAnimation({super.key});

  @override
  State<_WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<_WaveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 🔹 Bell-curve height profile matching the screenshot
  static const List<double> _baseHeights = [
    4, 7, 11, 15, 19, 15, 23, 15, 19, 15, 11, 7, 4,
  ];

  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    // Single controller for all bars — 1200 ms full cycle
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: false); // 🔹 loops forward continuously

    // 🔹 Each bar gets its own Interval slice so they're staggered
    _animations = List.generate(_baseHeights.length, (i) {
      // spread start offsets evenly between 0.0 and 0.6
      final double start = (i / _baseHeights.length) * 0.6;
      final double end = start + 0.4; // each bar animates over 40 % of the cycle

      return TweenSequence<double>([
        // rise
        TweenSequenceItem(
          tween: Tween<double>(
            begin: _baseHeights[i] * 0.3,
            end: _baseHeights[i],
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
        // fall
        TweenSequenceItem(
          tween: Tween<double>(
            begin: _baseHeights[i],
            end: _baseHeights[i] * 0.3,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end.clamp(0.0, 1.0)),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // ✅ single controller, safe dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_baseHeights.length, (i) {
              return Container(
                width: 2.4,
                height: _animations[i].value.clamp(2.0, 30.0), // 🔹 clamp prevents 0-height render glitch
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                decoration: BoxDecoration(
                  color: const Color(0xFFCE5DE5),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// 📌 SECTION: Output Box
class _OutputBox extends StatelessWidget {
  final String translatedText;
  final bool isRTL;
  final VoidCallback onBookmark;
  final VoidCallback onCopy;

  const _OutputBox({
    required this.translatedText,
    required this.isRTL,
    required this.onBookmark,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onBookmark,
                child: SvgPicture.asset(
                  'assets/icons/bookmark.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onCopy,
                child: SvgPicture.asset(
                  'assets/icons/outline_duplicate.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (translatedText.isNotEmpty)
            Directionality(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              child: Align(
                alignment: isRTL ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  translatedText,
                  textAlign: isRTL ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 25),

          Align(
            alignment: Alignment.bottomRight,
            child: SvgPicture.asset(
              'assets/icons/speech.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            ),
          ),
        ],
      ),
    );
  }
}