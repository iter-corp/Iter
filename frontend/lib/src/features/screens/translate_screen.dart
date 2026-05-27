import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
import '../widgets/feature_disabled_view.dart';
import '../widgets/primary_action_button.dart';
import 'saved_translations_screen.dart';

// Languages: see [kTranslateLanguages] in translate_service.dart for the
// canonical list shared with chat / comment / post translate pickers.
TranslateLanguage _langByLabel(String label) => kTranslateLanguages
    .firstWhere((l) => l.label == label, orElse: () => kTranslateLanguages.first);

class TranslateBody extends ConsumerStatefulWidget {
  const TranslateBody({super.key});

  @override
  ConsumerState<TranslateBody> createState() => _TranslateBodyState();
}

class _TranslateBodyState extends ConsumerState<TranslateBody> {
  String _sourceLang = 'English (USA)';
  String _targetLang = 'Kurdish (Sorani)';
  final TextEditingController _inputController = TextEditingController();
  final TranslateService _translateService = const TranslateService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _sttInitialized = false;
  String _translatedText = '';
  bool _hasTranslation = false;
  bool _isRecording = false;
  bool _isTranslating = false;

  // ── TTS ──
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // ── Bookmark ──
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _inputController.dispose();
    super.dispose();
  }

  String _friendlySttError(AppStrings t, String code) {
    switch (code) {
      case 'error_no_match':
        return t.translateSttNoMatch;
      case 'error_speech_timeout':
      case 'error_no_speech':
        return t.translateSttNoSpeech;
      case 'error_audio':
        return t.translateSttAudio;
      case 'error_network':
      case 'error_network_timeout':
        return t.translateSttNetwork;
      case 'error_permission':
        return t.translateSttPermission;
      default:
        return t.translateSttGeneric(code);
    }
  }

  Future<void> _toggleListen() async {
    if (_isRecording) {
      await _speech.stop();
      if (mounted) setState(() => _isRecording = false);
      return;
    }

    if (!_sttInitialized) {
      _sttInitialized = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _isRecording = false);
          }
        },
        onError: (err) {
          debugPrint('[stt] error: ${err.errorMsg}');
          if (!mounted) return;
          setState(() => _isRecording = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_friendlySttError(context.t, err.errorMsg)),
            ),
          );
        },
      );
      if (!_sttInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.translateMicNotAvailable)),
          );
        }
        return;
      }
    }

    // Pick a locale the device actually supports. Not all the languages
    // in our picker have an installed STT engine — fall back to the device
    // default so speak-to-translate still works.
    final requested = _langByLabel(_sourceLang).stt ?? 'en_US';
    final installed = await _speech.locales();
    var match = installed.firstWhere(
      (l) =>
          l.localeId == requested ||
          l.localeId.replaceAll('-', '_') == requested ||
          l.localeId.replaceAll('_', '-') == requested,
      orElse: () => stt.LocaleName('', ''),
    );

    if (match.localeId.isEmpty) {
      // Try to match just the primary language code (e.g., 'ar' or 'en')
      final prefix = requested.split(RegExp(r'[-_]')).first;
      match = installed.firstWhere(
        (l) => l.localeId.startsWith(prefix),
        orElse: () => stt.LocaleName('', ''),
      );
    }

    if (match.localeId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(context.t.translateSttUnsupported(_sourceLang)),
          ),
        );
      }
      return;
    }
    setState(() => _isRecording = true);
    await _speech.listen(
      localeId: match.localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        });
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _onTranslate();
        }
      },
    );
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

  Future<void> _onTranslate() async {
    final input = _inputController.text.trim();
    if (input.isEmpty || _isTranslating) return;
    setState(() => _isTranslating = true);

    final sourceCode = _langByLabel(_sourceLang).code;
    final targetCode = _langByLabel(_targetLang).code;

    try {
      final translated = await _translateService.translateText(
        text: input,
        sourceLang: sourceCode,
        targetLang: targetCode,
      );
      if (!mounted) return;
      setState(() {
        _hasTranslation = true;
        _translatedText = translated;
        _isBookmarked = false; // new result → not yet saved
      });
      // Stop any ongoing TTS from the previous result.
      if (_isSpeaking) _tts.stop();
    } catch (e, st) {
      debugPrint('[translate] failed: $e');
      debugPrint('[translate] stack: $st');
      if (!mounted) return;
      final message = TranslateService.userFriendlyErrorMessage(e);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.t.translateUnavailable),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.t.ok),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  void _copyToClipboard() {
    if (_translatedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _translatedText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.translateCopied),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openSaved() async {
    final result = await Navigator.push<SavedTranslation?>(
      context,
      MaterialPageRoute(builder: (_) => const SavedTranslationsScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (kTranslateLanguages.any((l) => l.label == result.sourceLangLabel)) {
        _sourceLang = result.sourceLangLabel;
      }
      if (kTranslateLanguages.any((l) => l.label == result.targetLangLabel)) {
        _targetLang = result.targetLangLabel;
      }
      _inputController.text = result.sourceText;
      _translatedText = result.translatedText;
      _hasTranslation = true;
      _isBookmarked = true;
    });
  }

  // ── Bookmark: Save translation to Firestore ──
  Future<void> _toggleBookmark() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _translatedText.isEmpty) return;

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedTranslations');

    if (_isBookmarked) {
      // Remove: find and delete the matching doc.
      final snap = await col
          .where('sourceText', isEqualTo: _inputController.text.trim())
          .where('targetLang', isEqualTo: _langByLabel(_targetLang).code)
          .limit(1)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      if (!mounted) return;
      setState(() => _isBookmarked = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.translateRemovedFromSaved),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Save the translation.
      await col.add({
        'sourceText': _inputController.text.trim(),
        'translatedText': _translatedText,
        'sourceLang': _langByLabel(_sourceLang).code,
        'sourceLangLabel': _sourceLang,
        'targetLang': _langByLabel(_targetLang).code,
        'targetLangLabel': _targetLang,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _isBookmarked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.translateSaved),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final translateEnabled =
        ref.watch(adminConfigProvider).valueOrNull?.translateEnabled ?? true;
    if (!translateEnabled) {
      return const FeatureDisabledView(
        feature: 'Translate',
        icon: Icons.translate_outlined,
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 📌 Title + saved translations shortcut
                Row(
                  children: [
                    Text(
                      context.t.translate,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: context.t.savedTranslations,
                      onPressed: _openSaved,
                      icon: Icon(Icons.bookmarks_outlined,
                          color: context.textPrimary),
                    ),
                  ],
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
                  onMicTap: _toggleListen,
                  sourceLang: _sourceLang,
                ),
                const SizedBox(height: 16),

                // 📌 Translate Button
                PrimaryActionButton(
                  label: context.t.translate,
                  onPressed: _isTranslating ? null : _onTranslate,
                  loading: _isTranslating,
                  size: PrimaryActionSize.large,
                  fullWidth: true,
                ),
                const SizedBox(height: 16),

                // 📌 Output Box
                _OutputBox(
                  translatedText: _hasTranslation ? _translatedText : '',
                  isRTL: _langByLabel(_targetLang).rtl,
                  isBookmarked: _isBookmarked,
                  onBookmark: _toggleBookmark,
                  onCopy: _copyToClipboard,
                ),
              ],
            ),
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
        Expanded(
            child: _LanguageDropdown(
                value: sourceLang, onChanged: onSourceChanged)),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onSwap,
          child: Container(
            width: 33,
            height: 33,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.purpleVivid,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purple.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SvgPicture.asset(
              'assets/icons/swap.svg',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: _LanguageDropdown(
                value: targetLang, onChanged: onTargetChanged)),
      ],
    );
  }
}

// 📌 SECTION: Language Picker (searchable bottom sheet)
class _LanguageDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({required this.value, required this.onChanged});

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagePickerSheet(current: value),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: AppGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 12,
        surfaceAlpha: context.isDark ? 0.28 : 0.54,
        borderAlpha: context.isDark ? 0.18 : 0.52,
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: context.textPrimary, size: 20),
          ],
        ),
      ),
    );
  }
}

// 📌 SECTION: Language Picker Sheet (search)
class _LanguagePickerSheet extends StatefulWidget {
  final String current;
  const _LanguagePickerSheet({required this.current});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? kTranslateLanguages
        : kTranslateLanguages
            .where((l) =>
                l.label.toLowerCase().contains(q) ||
                l.code.toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: context.textSecondary),
                  hintText: context.t.translateSearchLanguages,
                  hintStyle: TextStyle(color: context.textMuted),
                  filled: true,
                  fillColor: context.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
                style: TextStyle(color: context.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        context.t.translateNoLanguagesMatch,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final lang = filtered[i];
                        final isCurrent = lang.label == widget.current;
                        return ListTile(
                          title: Text(lang.label,
                              style: TextStyle(color: context.textPrimary)),
                          subtitle: Text(
                            lang.code,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check,
                                  color: AppColors.purpleVivid)
                              : null,
                          onTap: () => Navigator.pop(context, lang.label),
                        );
                      },
                    ),
            ),
          ],
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
  final String sourceLang;

  const _InputBox({
    required this.controller,
    required this.onMicTap,
    required this.isRecording,
    required this.sourceLang,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
      height: 136,
      radius: 22,
      emphasize: true,
      surfaceAlpha: context.isDark ? 0.18 : 0.48,
      borderAlpha: context.isDark ? 0.24 : 0.56,
      child: Stack(
        children: [
          TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: context.t.translateEnterText,
              hintStyle: TextStyle(
                fontSize: 15,
                color: context.textMuted.withValues(alpha: 0.78),
                fontWeight: FontWeight.w600,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.only(right: 42, bottom: 28),
            ),
            style: TextStyle(
              fontSize: 15,
              color: context.textPrimary,
              fontWeight: FontWeight.w600,
            ),
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
                        colorFilter: ColorFilter.mode(
                          context.textPrimary,
                          BlendMode.srcIn,
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
    4,
    7,
    11,
    15,
    19,
    15,
    23,
    15,
    19,
    15,
    11,
    7,
    4,
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
      final double end =
          start + 0.4; // each bar animates over 40 % of the cycle

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
                height: _animations[i].value.clamp(
                    2.0, 30.0), // 🔹 clamp prevents 0-height render glitch
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                decoration: BoxDecoration(
                  color: AppColors.purpleVivid,
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
  final bool isBookmarked;
  final VoidCallback onBookmark;
  final VoidCallback onCopy;

  const _OutputBox({
    required this.translatedText,
    required this.isRTL,
    this.isBookmarked = false,
    required this.onBookmark,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.all(14),
      radius: 22,
      surfaceAlpha: context.isDark ? 0.24 : 0.54,
      borderAlpha: context.isDark ? 0.16 : 0.50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // 🔖 Bookmark — toggles filled/outline
              GestureDetector(
                onTap: translatedText.isNotEmpty ? onBookmark : null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isBookmarked
                      ? const Icon(
                          Icons.bookmark,
                          key: ValueKey('filled'),
                          size: 22,
                          color: AppColors.purpleVivid,
                        )
                      : SvgPicture.asset(
                          key: const ValueKey('outline'),
                          'assets/icons/Bookmark.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                              context.textPrimary, BlendMode.srcIn),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // 📋 Copy
              GestureDetector(
                onTap: onCopy,
                child: SvgPicture.asset(
                  'assets/icons/outline_duplicate.svg',
                  width: 20,
                  height: 20,
                  colorFilter:
                      ColorFilter.mode(context.textPrimary, BlendMode.srcIn),
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                    height: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
