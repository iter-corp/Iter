import 'package:cloud_firestore/cloud_firestore.dart';

class ProfanityFilterService {
  final FirebaseFirestore _db;
  final Duration cacheTtl;

  ProfanityFilterService({
    FirebaseFirestore? db,
    this.cacheTtl = const Duration(minutes: 10),
  }) : _db = db ?? FirebaseFirestore.instance;

  static const Set<String> _fallbackWords = {
    'arse',
    'asshole',
    'bastard',
    'bitch',
    'bloody',
    'bollocks',
    'bullshit',
    'crap',
    'damn',
    'dick',
    'freaking',
    'fuck',
    'fucker',
    'fucking',
    'goddamn',
    'hell',
    'motherfucker',
    'piss',
    'prick',
    'shit',
    'slut',
    'whore',
    'wanker',
  };

  Set<String>? _cachedWords;
  DateTime? _lastLoadedAt;

  Future<Set<String>> _loadWords() async {
    final now = DateTime.now();
    if (_cachedWords != null &&
        _lastLoadedAt != null &&
        now.difference(_lastLoadedAt!) < cacheTtl) {
      return _cachedWords!;
    }

    try {
      final snap = await _db.collection('adminConfig').doc('app').get();
      final data = snap.data();
      final raw = data?['profanityWordsEn'];
      final list = raw is List ? raw : const [];
      final words = list
          .whereType<String>()
          .map((w) => _normalizeWord(w))
          .where((w) => w.isNotEmpty)
          .toSet();
      if (words.isNotEmpty) {
        _cachedWords = words;
        _lastLoadedAt = now;
        return words;
      }
    } catch (_) {
      // Fall back to the built-in list when config read fails.
    }

    _cachedWords = _fallbackWords;
    _lastLoadedAt = now;
    return _cachedWords!;
  }

  Future<List<String>> findMatches(String text) async {
    final words = await _loadWords();
    if (text.trim().isEmpty) return const [];

    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .map(_normalizeWord)
        .where((t) => t.isNotEmpty)
        .toSet();

    final matches = tokens.where(words.contains).toList()..sort();
    return matches;
  }

  String _normalizeWord(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  }
}
