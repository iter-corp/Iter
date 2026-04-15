import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../services/translate_service.dart';

// 📌 SECTION: Supported Languages
//
// Gemini handles virtually any language. We keep a broad list here, with the
// ISO-639 code Gemini should receive, plus an optional BCP-47 locale for
// on-device speech-to-text. Languages without a `stt` locale fall back to the
// device default; live transcription may be less accurate for those.
class _Language {
  final String label;
  final String code;
  final String? stt;
  final bool rtl;
  const _Language(this.label, this.code, {this.stt, this.rtl = false});
}

const List<_Language> _kLanguages = [
  _Language('English (USA)', 'en', stt: 'en_US'),
  _Language('English (UK)', 'en', stt: 'en_GB'),
  _Language('Arabic', 'ar', stt: 'ar_SA', rtl: true),
  _Language('Kurdish (Sorani)', 'ckb', stt: 'ar_IQ', rtl: true),
  _Language('Kurdish (Kurmanji)', 'kmr', stt: 'tr_TR'),
  _Language('Persian', 'fa', stt: 'fa_IR', rtl: true),
  _Language('Turkish', 'tr', stt: 'tr_TR'),
  _Language('Spanish', 'es', stt: 'es_ES'),
  _Language('French', 'fr', stt: 'fr_FR'),
  _Language('German', 'de', stt: 'de_DE'),
  _Language('Italian', 'it', stt: 'it_IT'),
  _Language('Portuguese (Brazil)', 'pt-BR', stt: 'pt_BR'),
  _Language('Portuguese (Portugal)', 'pt-PT', stt: 'pt_PT'),
  _Language('Russian', 'ru', stt: 'ru_RU'),
  _Language('Ukrainian', 'uk', stt: 'uk_UA'),
  _Language('Polish', 'pl', stt: 'pl_PL'),
  _Language('Dutch', 'nl', stt: 'nl_NL'),
  _Language('Swedish', 'sv', stt: 'sv_SE'),
  _Language('Norwegian', 'no', stt: 'nb_NO'),
  _Language('Danish', 'da', stt: 'da_DK'),
  _Language('Finnish', 'fi', stt: 'fi_FI'),
  _Language('Czech', 'cs', stt: 'cs_CZ'),
  _Language('Greek', 'el', stt: 'el_GR'),
  _Language('Hebrew', 'he', stt: 'he_IL', rtl: true),
  _Language('Urdu', 'ur', stt: 'ur_PK', rtl: true),
  _Language('Hindi', 'hi', stt: 'hi_IN'),
  _Language('Bengali', 'bn', stt: 'bn_IN'),
  _Language('Tamil', 'ta', stt: 'ta_IN'),
  _Language('Telugu', 'te', stt: 'te_IN'),
  _Language('Malay', 'ms', stt: 'ms_MY'),
  _Language('Indonesian', 'id', stt: 'id_ID'),
  _Language('Thai', 'th', stt: 'th_TH'),
  _Language('Vietnamese', 'vi', stt: 'vi_VN'),
  _Language('Japanese', 'ja', stt: 'ja_JP'),
  _Language('Korean', 'ko', stt: 'ko_KR'),
  _Language('Chinese (Simplified)', 'zh-CN', stt: 'zh_CN'),
  _Language('Chinese (Traditional)', 'zh-TW', stt: 'zh_TW'),
  _Language('Swahili', 'sw', stt: 'sw_KE'),
  _Language('Amharic', 'am', stt: 'am_ET'),
  _Language('Somali', 'so'),
  _Language('Hausa', 'ha'),
  _Language('Zulu', 'zu', stt: 'zu_ZA'),
  _Language('Afrikaans', 'af', stt: 'af_ZA'),
  _Language('Hungarian', 'hu', stt: 'hu_HU'),
  _Language('Romanian', 'ro', stt: 'ro_RO'),
  _Language('Bulgarian', 'bg', stt: 'bg_BG'),
  _Language('Serbian', 'sr', stt: 'sr_RS'),
  _Language('Croatian', 'hr', stt: 'hr_HR'),
  _Language('Slovak', 'sk', stt: 'sk_SK'),
  _Language('Slovenian', 'sl', stt: 'sl_SI'),
  _Language('Lithuanian', 'lt', stt: 'lt_LT'),
  _Language('Latvian', 'lv', stt: 'lv_LV'),
  _Language('Estonian', 'et', stt: 'et_EE'),
  _Language('Icelandic', 'is', stt: 'is_IS'),
  _Language('Catalan', 'ca', stt: 'ca_ES'),
  _Language('Basque', 'eu', stt: 'eu_ES'),
  _Language('Galician', 'gl', stt: 'gl_ES'),
  _Language('Welsh', 'cy'),
  _Language('Irish', 'ga'),
  _Language('Albanian', 'sq'),
  _Language('Armenian', 'hy'),
  _Language('Azerbaijani', 'az'),
  _Language('Georgian', 'ka'),
  _Language('Kazakh', 'kk'),
  _Language('Uzbek', 'uz'),
  _Language('Mongolian', 'mn'),
  _Language('Khmer', 'km'),
  _Language('Lao', 'lo'),
  _Language('Burmese', 'my'),
  _Language('Filipino', 'fil', stt: 'fil_PH'),
  _Language('Nepali', 'ne'),
  _Language('Sinhala', 'si'),
  _Language('Pashto', 'ps', rtl: true),
  _Language('Maltese', 'mt'),
  _Language('Esperanto', 'eo'),
];

_Language _langByLabel(String label) =>
    _kLanguages.firstWhere((l) => l.label == label,
        orElse: () => _kLanguages.first);

class TranslateBody extends StatefulWidget {
  const TranslateBody({super.key});

  @override
  State<TranslateBody> createState() => _TranslateBodyState();
}

class _TranslateBodyState extends State<TranslateBody> {
  String _sourceLang = 'English (USA)';
  String _targetLang = 'Kurdish (Sorani)';
  final TextEditingController _inputController = TextEditingController();
  final TranslateService _translateService = TranslateService();
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

  String _friendlySttError(String code) {
    switch (code) {
      case 'error_no_match':
        return "Couldn't recognize speech. Make sure the source language matches what you're saying.";
      case 'error_speech_timeout':
      case 'error_no_speech':
        return 'No speech detected. Try again and speak closer to the mic.';
      case 'error_audio':
        return 'Mic audio error. Close other apps using the mic and retry.';
      case 'error_network':
      case 'error_network_timeout':
        return 'Network error. Speech recognition needs internet.';
      case 'error_permission':
        return 'Mic permission denied. Enable it in device settings.';
      default:
        return 'Mic error: $code';
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
            SnackBar(content: Text(_friendlySttError(err.errorMsg))),
          );
        },
      );
      if (!_sttInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone not available. Check permission.'),
            ),
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
            content: Text('Speech-to-text not supported for $_sourceLang on this device.'),
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
        if (result.finalResult &&
            result.recognizedWords.trim().isNotEmpty) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Translate failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
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
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── TTS: Speak the translated text ──
  Future<void> _toggleSpeak() async {
    if (_translatedText.isEmpty) return;

    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }

    // Map our language code to a BCP-47 locale the TTS engine understands.
    final lang = _langByLabel(_targetLang);
    final locale = lang.stt ?? lang.code; // stt field is BCP-47 when available
    await _tts.setLanguage(locale.replaceAll('_', '-'));
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    setState(() => _isSpeaking = true);
    await _tts.speak(_translatedText);
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
        const SnackBar(
          content: Text('Translation removed from saved'),
          duration: Duration(seconds: 2),
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
        const SnackBar(
          content: Text('Translation saved!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EAF0),
      body: SafeArea(
        child: SingleChildScrollView(
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
                onMicTap: _toggleListen,
                sourceLang: _sourceLang,
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
                    child: _isTranslating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
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
                isRTL: _langByLabel(_targetLang).rtl,
                isBookmarked: _isBookmarked,
                isSpeaking: _isSpeaking,
                onBookmark: _toggleBookmark,
                onCopy: _copyToClipboard,
                onSpeak: _toggleSpeak,
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
            decoration: const BoxDecoration(
              color: Color(0xFFCE5DE5),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: SvgPicture.asset(
              'assets/icons/swap.svg',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              colorFilter:
                  const ColorFilter.mode(Colors.black, BlendMode.srcIn),
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
      backgroundColor: Colors.white,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFD7D7D7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.black, size: 20),
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
        ? _kLanguages
        : _kLanguages
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
                color: Colors.grey.shade300,
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
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search languages',
                  filled: true,
                  fillColor: const Color(0xFFF0F0F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No languages match',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final lang = filtered[i];
                        final isCurrent = lang.label == widget.current;
                        return ListTile(
                          title: Text(lang.label),
                          subtitle: Text(
                            lang.code,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check,
                                  color: Color(0xFFCE5DE5))
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
            style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                fontWeight: FontWeight.bold),
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
                        colorFilter: const ColorFilter.mode(
                            Colors.black, BlendMode.srcIn),
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
  final bool isBookmarked;
  final bool isSpeaking;
  final VoidCallback onBookmark;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;

  const _OutputBox({
    required this.translatedText,
    required this.isRTL,
    this.isBookmarked = false,
    this.isSpeaking = false,
    required this.onBookmark,
    required this.onCopy,
    required this.onSpeak,
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
            color: Colors.black.withValues(alpha: 0.04),
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
                          color: Color(0xFFCE5DE5),
                        )
                      : SvgPicture.asset(
                          key: const ValueKey('outline'),
                          'assets/icons/Bookmark.svg',
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                              Colors.black, BlendMode.srcIn),
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
                      const ColorFilter.mode(Colors.black, BlendMode.srcIn),
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
          // 🔊 TTS — tappable with visual feedback
          Align(
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              onTap: translatedText.isNotEmpty ? onSpeak : null,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isSpeaking
                    ? const Icon(
                        Icons.stop_circle_outlined,
                        key: ValueKey('stop'),
                        size: 22,
                        color: Color(0xFFCE5DE5),
                      )
                    : SvgPicture.asset(
                        key: const ValueKey('speaker'),
                        'assets/icons/speech.svg',
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(
                          translatedText.isNotEmpty
                              ? Colors.black
                              : Colors.grey,
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
