// Shared world-city source.
//
// Every place that lets the user pick a city — Create Post, Onboarding,
// the Connect-tab people filter, the Events filter, Travel search — goes
// through here so they all draw from ONE canonical list. Backed by the
// offline `country_state_city` package (~40k cities, no network, no API
// key), loaded lazily the first time a picker is opened and cached for
// the rest of the app session.

import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Normalises a string for accent/locale-insensitive city matching.
/// Used both when building the search haystack and when matching a
/// query, so a search for "izmir" finds "İzmir" and "sao paulo" finds
/// "São Paulo".
String normalizeCitySearch(String input) {
  var out = removeDiacritics(input).toLowerCase().trim();
  const replacements = {
    'ı': 'i',
    'İ': 'i',
    'ñ': 'n',
    'ç': 'c',
    'ş': 's',
    'ğ': 'g',
    'ý': 'y',
    'ÿ': 'y',
    'æ': 'ae',
    'œ': 'oe',
  };
  replacements.forEach((from, to) {
    out = out.replaceAll(from, to);
  });
  out = out.replaceAll(RegExp(r"[^a-z0-9\s-]"), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

/// One city in the shared list, with precomputed search fields.
class CityOption {
  final String name;
  final String countryCode;

  /// Full country name (e.g. "Georgia"), resolved from the ISO code.
  /// Falls back to the ISO code when the country can't be resolved.
  final String countryName;
  final String stateCode;
  final String normalizedName;
  final String searchHaystack;

  const CityOption({
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.stateCode,
    required this.normalizedName,
    required this.searchHaystack,
  });

  /// "Tbilisi, Georgia" — the value stored/displayed when a city is
  /// chosen. Falls back to just the city name if no country is known.
  String get displayLabel =>
      countryName.isEmpty ? name : '$name, $countryName';

  /// Secondary line under the city name in the picker list.
  String get regionLabel =>
      [stateCode, countryName].where((s) => s.isNotEmpty).join(' • ');
}

/// Loads, de-dupes and sorts the full world-city list exactly once.
/// `AsyncNotifierProvider` keeps the result cached app-wide; the heavy
/// `getAllCities()` call only runs the first time the provider is read.
final worldCitiesProvider =
    AsyncNotifierProvider<WorldCitiesNotifier, List<CityOption>>(
  WorldCitiesNotifier.new,
);

class WorldCitiesNotifier extends AsyncNotifier<List<CityOption>> {
  @override
  Future<List<CityOption>> build() async {
    // Resolve ISO country codes → full names so the picker can show
    // "City, Country" instead of "City, GE".
    final countries = await csc.getAllCountries();
    final countryNames = <String, String>{
      for (final c in countries) c.isoCode.toUpperCase(): c.name.trim(),
    };

    final all = await csc.getAllCities();
    final dedup = <String, CityOption>{};
    for (final city in all) {
      final name = city.name.trim();
      if (name.isEmpty) continue;
      final country = city.countryCode.trim();
      final state = city.stateCode.trim();
      final countryName = countryNames[country.toUpperCase()] ?? country;
      final key =
          '${name.toLowerCase()}|${country.toLowerCase()}|${state.toLowerCase()}';
      dedup[key] = CityOption(
        name: name,
        countryCode: country,
        countryName: countryName,
        stateCode: state,
        normalizedName: normalizeCitySearch(name),
        // Country name is part of the haystack so "tbilisi georgia" and
        // a plain "georgia" search both find the city.
        searchHaystack:
            normalizeCitySearch('$name $countryName $country $state'),
      );
    }
    final out = dedup.values.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        final byCountry =
            a.countryCode.toLowerCase().compareTo(b.countryCode.toLowerCase());
        if (byCountry != 0) return byCountry;
        return a.stateCode.toLowerCase().compareTo(b.stateCode.toLowerCase());
      });
    return out;
  }
}

/// Ranks [cities] against [rawQuery]. Empty query returns the list
/// unchanged. Exact match ranks above prefix, above word-boundary,
/// above substring; ties broken by closeness in length then name.
List<CityOption> rankCities(List<CityOption> cities, String rawQuery) {
  final q = normalizeCitySearch(rawQuery);
  if (q.isEmpty) return cities;

  final ranked = <({int score, int lenDelta, CityOption city})>[];
  for (final city in cities) {
    if (!city.searchHaystack.contains(q)) continue;

    int score;
    if (city.normalizedName == q) {
      score = 0;
    } else if (city.normalizedName.startsWith(q)) {
      score = 1;
    } else if (city.normalizedName
        .split(RegExp(r'[\s-]+'))
        .any((part) => part.startsWith(q))) {
      score = 2;
    } else {
      score = 3;
    }

    ranked.add((
      score: score,
      lenDelta: (city.normalizedName.length - q.length).abs(),
      city: city,
    ));
  }

  ranked.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    if (byScore != 0) return byScore;
    final byLen = a.lenDelta.compareTo(b.lenDelta);
    if (byLen != 0) return byLen;
    final byName =
        a.city.name.toLowerCase().compareTo(b.city.name.toLowerCase());
    if (byName != 0) return byName;
    return a.city.countryCode
        .toLowerCase()
        .compareTo(b.city.countryCode.toLowerCase());
  });

  return ranked.map((item) => item.city).toList();
}

/// Sentinel returned by [showCityPicker] when the optional "Nearby" row
/// is tapped, so callers can switch to GPS-based filtering.
const String kCityPickerNearby = '__city_picker_nearby__';

/// Opens the shared city-picker bottom sheet and resolves to the chosen
/// city name, or null if dismissed. Triggers the lazy world-city load.
///
/// When [showNearby] is true a pinned "Nearby" row appears at the top of
/// the list; tapping it resolves to [kCityPickerNearby].
Future<String?> showCityPicker(
  BuildContext context, {
  String initialQuery = '',
  bool showNearby = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CityPickerSheet(
      initialQuery: initialQuery,
      showNearby: showNearby,
    ),
  );
}

class _CityPickerSheet extends ConsumerStatefulWidget {
  final String initialQuery;
  final bool showNearby;
  const _CityPickerSheet({
    required this.initialQuery,
    this.showNearby = false,
  });

  @override
  ConsumerState<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends ConsumerState<_CityPickerSheet> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final citiesAsync = ref.watch(worldCitiesProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.t.cityPickerSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: citiesAsync.when(
                  loading: () => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          context.t.cityPickerLoading,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  error: (_, __) => Center(
                    child: Text(
                      context.t.cityPickerNoResults,
                      style: TextStyle(color: context.textSecondary),
                    ),
                  ),
                  data: (allCities) {
                    final results = rankCities(allCities, _searchCtrl.text);
                    // The "Nearby" row is pinned at the top, but only
                    // while the user hasn't typed a search query.
                    final showNearbyRow = widget.showNearby &&
                        _searchCtrl.text.trim().isEmpty;
                    if (results.isEmpty && !showNearbyRow) {
                      return Center(
                        child: Text(
                          context.t.cityPickerNoResults,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      );
                    }
                    final nearbyOffset = showNearbyRow ? 1 : 0;
                    return ListView.separated(
                      itemCount: results.length + nearbyOffset,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: context.borderColor,
                      ),
                      itemBuilder: (_, index) {
                        if (showNearbyRow && index == 0) {
                          return ListTile(
                            leading: const Icon(
                              Icons.my_location_rounded,
                              color: Color(0xFF7E3BE8),
                            ),
                            title: Text(context.t.eventsFilterNearby),
                            onTap: () =>
                                Navigator.pop(context, kCityPickerNearby),
                          );
                        }
                        final city = results[index - nearbyOffset];
                        return ListTile(
                          title: Text(city.name),
                          subtitle: city.regionLabel.isEmpty
                              ? null
                              : Text(city.regionLabel),
                          // Return "City, Country" so the value stored
                          // everywhere carries the country.
                          onTap: () =>
                              Navigator.pop(context, city.displayLabel),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A read-only field styled like an input that opens [showCityPicker]
/// when tapped. Drop-in city selector for forms.
class CityPickerField extends StatelessWidget {
  /// Current selected city name (empty = nothing chosen).
  final String value;

  /// Called with the chosen city name when the user picks one.
  final ValueChanged<String> onChanged;

  /// Called when the user taps the inline clear (✕) button.
  final VoidCallback? onClear;

  final String? hintText;
  final IconData icon;
  final bool glassy;

  const CityPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onClear,
    this.hintText,
    this.icon = Icons.location_city_outlined,
    this.glassy = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showCityPicker(context, initialQuery: v);
          if (picked != null && picked.isNotEmpty) onChanged(picked);
        },
        child: Container(
          decoration: BoxDecoration(
            color: glassy
                ? (context.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.28))
                : context.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: glassy
                  ? (context.isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.50))
                  : context.borderColor,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF7E3BE8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.isEmpty ? (hintText ?? context.t.cityPickerSelect) : v,
                  style: TextStyle(
                    color: v.isEmpty
                        ? context.textSecondary
                        : context.textPrimary,
                  ),
                ),
              ),
              if (v.isNotEmpty && onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: context.textSecondary,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
