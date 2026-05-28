# Localization

The Iter app ships fully translated UI text in three languages, with English as the source of truth. Translation is implemented with plain Dart maps + getter wrappers — no codegen, no `.arb` files. There are ~**1253 string keys** in the English source.

## Supported languages

Defined as the `AppLanguage` enum in [`lib/src/providers/locale_provider.dart`](../../lib/src/providers/locale_provider.dart):

| Enum | `code` | English name | Native name | Direction |
|---|---|---|---|---|
| `AppLanguage.english` | `en` | English | English | LTR |
| `AppLanguage.arabic` | `ar` | Arabic | العربية | RTL |
| `AppLanguage.kurdish` | `ckb` | Kurdish (Sorani) | کوردیی ناوەندی | RTL |

`ckb` is the ISO-639-3 code for Central Kurdish (Sorani). `AppLanguage.fromCode(String?)` looks up by code, falling back to English.

## Architecture

Four files compose the system, all under [`lib/src/l10n/`](../../lib/src/l10n/):

| File | Role | Lines |
|---|---|---|
| [`strings_en.dart`](../../lib/src/l10n/strings_en.dart) | **Source of truth.** `const Map<String, String> enStrings = { 'key': 'English value', … }`. Every key the UI can render is defined here. | ~1641 |
| [`strings_ar.dart`](../../lib/src/l10n/strings_ar.dart) | `arStrings` — same keys, Arabic translations. | ~1601 |
| [`strings_ckb.dart`](../../lib/src/l10n/strings_ckb.dart) | `ckbStrings` — same keys, Kurdish Sorani translations. | ~1625 |
| [`app_strings.dart`](../../lib/src/l10n/app_strings.dart) | `AppStrings` class + `extension AppStringsX on BuildContext` exposing `context.t`. Holds one getter / parameterized method per key. | ~1945 |
| [`ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart) | Custom `LocalizationsDelegate`s for `ckb` that proxy to Flutter's bundled Arabic localizations (Material / Cupertino / Widgets). | 95 |

### Lookup mechanism

The `AppStrings` class wraps the three maps:

```dart
class AppStrings {
  const AppStrings(this.language);
  final AppLanguage language;

  static const Map<AppLanguage, Map<String, String>> _tables = {
    AppLanguage.english: enStrings,
    AppLanguage.arabic:  arStrings,
    AppLanguage.kurdish: ckbStrings,
  };

  String _get(String key) =>
      _tables[language]?[key] ?? enStrings[key] ?? key;

  String _fmt(String key, Map<String, Object?> args) {
    var out = _get(key);
    args.forEach((name, value) => out = out.replaceAll('{$name}', '$value'));
    return out;
  }
}
```

The fallback chain is **active language → English → the key string itself**. So a Kurdish translation that's missing degrades to English (never crashes). Only a developer-error key (one that's missing in English too) shows the raw key.

Every UI string is exposed as a getter or a method on `AppStrings`. Examples:

```dart
String get cancel             => _get('cancel');
String get loading            => _get('loading');
String likesCount(Object n)   => _fmt('likes_count', {'count': n});
String storyShared(Object n)  => _fmt('story_shared', {'name': n});
String reportReasonLabel(String englishReason) { switch (englishReason) { ... } }
```

`_fmt` performs simple `{placeholder}` substitution — unknown placeholders are left untouched.

### `context.t` — the access pattern

The bottom of [`app_strings.dart`](../../lib/src/l10n/app_strings.dart) defines:

```dart
extension AppStringsX on BuildContext {
  AppStrings get t {
    final code = Localizations.localeOf(this).languageCode;
    return AppStrings(AppLanguage.fromCode(code));
  }
}
```

Reading `Localizations.localeOf(this)` makes every widget that uses `context.t` rebuild automatically when the locale changes — no manual subscription needed.

Usage in widgets:

```dart
Text(context.t.settings)             // simple key
Text(context.t.helloName('Sara'))    // parameterized helper
Text(context.t.likesCount(post.likesCount))
```

## `localeProvider` — persistence + active language

File: [`lib/src/providers/locale_provider.dart`](../../lib/src/providers/locale_provider.dart).

`StateNotifierProvider<LocaleNotifier, AppLanguage>` backed by the pre-loaded `SharedPreferences` instance (same one used by `themeModeProvider`).

- SharedPreferences key: `app_ui_language`.
- First launch:
  - If no saved value, reads `ui.PlatformDispatcher.instance.locale.languageCode` and falls back to English when not in our supported list.
- Subsequent launches: the saved choice wins.
- API: `setLanguage(AppLanguage)` — no-ops when already on that language.

The provider is consumed in `main.dart`:

```dart
final language = ref.watch(localeProvider);
return MaterialApp.router(
  locale: language.locale,
  supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
  ...
);
```

Changing the value triggers a `MaterialApp` rebuild, which rebuilds `Localizations`, which rebuilds every `context.t` reader, and also flips `TextDirection` for RTL languages — no app restart required.

## RTL / text-direction handling

Each `AppLanguage` carries its own `TextDirection`:

```dart
english: TextDirection.ltr,
arabic:  TextDirection.rtl,
kurdish: TextDirection.rtl,
```

`AppLanguage.isRtl` is a convenience getter. The app does NOT manually wrap subtrees in `Directionality` — instead, when the active locale's language code is RTL, Flutter's `WidgetsLocalizations` provides the right ambient `TextDirection` automatically. That works for `ar` out of the box and for `ckb` because of the custom Widgets delegate (see below).

For RTL-aware layout, use:
- `AnimatedPositionedDirectional` (used in the floating bottom nav bubble in `main_screen.dart`).
- `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`.

## The Kurdish (`ckb`) Material localizations hack

Flutter's `flutter_localizations` package ships with ~80 locales, but **Kurdish Sorani is NOT one of them**. Without a delegate that claims `ckb`, framework widgets (date pickers, dialog buttons, the implicit `Directionality`, semantics tooltips) would throw `"No <Foo>Localizations found"`.

[`ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart) solves this by **proxying every `ckb` request to Flutter's Arabic (`ar`) localization**. Kurdish Sorani is written in Arabic script and is RTL, so Arabic's bundled stock strings (e.g. the "Cancel" button inside a system date picker) are an acceptable fallback. The app's own UI text still comes from `strings_ckb.dart`; only framework chrome falls back.

Three delegates are exported:

| Delegate | Backing locale | Purpose |
|---|---|---|
| `CkbMaterialLocalizations.delegate` | `Locale('ar')` | Material widgets (`Cancel`, date pickers, etc.) |
| `CkbCupertinoLocalizations.delegate` | `Locale('ar')` | iOS-style widgets |
| `CkbWidgetsLocalizations.delegate` | `Locale('ar')` | Ambient `TextDirection` for the whole `ckb` subtree |

All three are registered in `main.dart` ahead of the `GlobalXxxLocalizations.delegate`s so Flutter picks them when the active locale is `ckb`:

```dart
localizationsDelegates: const [
  CkbMaterialLocalizations.delegate,
  CkbCupertinoLocalizations.delegate,
  CkbWidgetsLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

Each `isSupported` returns `locale.languageCode == 'ckb'`. `load()` returns the corresponding `Global*.load(Locale('ar'))`.

## Adding a new key — workflow

1. Add the key to **all three** strings files. English is the source of truth, so write the English value first.
   ```dart
   // strings_en.dart
   'my_new_key': 'Hello {name}',
   // strings_ar.dart
   'my_new_key': 'مرحبا {name}',
   // strings_ckb.dart
   'my_new_key': 'سڵاو {name}',
   ```
2. Add a getter or method to [`AppStrings`](../../lib/src/l10n/app_strings.dart) in the right section:
   ```dart
   String myNewKey(Object name) => _fmt('my_new_key', {'name': name});
   ```
3. Use it in widgets via `context.t.myNewKey(user.name)`.

If you forget step 1 for `ar` or `ckb`, the key automatically falls back to English (no crash). If you forget to add the English value, the key string itself shows up — that's the "missed translation" signal.

## Other related concerns

- `TranslateService` (content translation between users' typed languages) is a SEPARATE concern — see [`lib/src/services/translate_service.dart`](../../lib/src/services/translate_service.dart) and `03-services.md`. It has its OWN `kTranslateLanguages` list (60+ entries) — that list is the catalog of "languages you can translate INTO inside the app", not the UI languages.
- The user's choice of translate-target lives in [`preferredLanguageProvider`](../../lib/src/providers/preferred_language_provider.dart) under SharedPreferences key `app_preferred_lang`. Distinct from the UI locale.
- The dedicated `/language` route (`LanguageScreen`) is the user-facing toggle for the UI locale.

## Related files

- [`lib/src/l10n/app_strings.dart`](../../lib/src/l10n/app_strings.dart) — `AppStrings` + `context.t`.
- [`lib/src/l10n/strings_en.dart`](../../lib/src/l10n/strings_en.dart) — English source of truth.
- [`lib/src/l10n/strings_ar.dart`](../../lib/src/l10n/strings_ar.dart) — Arabic translations.
- [`lib/src/l10n/strings_ckb.dart`](../../lib/src/l10n/strings_ckb.dart) — Kurdish Sorani translations.
- [`lib/src/l10n/ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart) — custom Material/Cupertino/Widgets delegates that map `ckb` onto Arabic.
- [`lib/src/providers/locale_provider.dart`](../../lib/src/providers/locale_provider.dart) — `AppLanguage` enum + `localeProvider`.
- [`lib/main.dart`](../../lib/main.dart) — `MaterialApp.router` wiring `locale`, `supportedLocales`, `localizationsDelegates`.
- [`lib/src/features/screens/language_screen.dart`](../../lib/src/features/screens/language_screen.dart) — the user-facing language picker.
