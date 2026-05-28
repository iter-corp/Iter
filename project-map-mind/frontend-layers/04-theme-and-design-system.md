# Theme & Design System

The app ships a single Material 3 theme defined in [`lib/src/theme/app_theme.dart`](../../lib/src/theme/app_theme.dart) with a custom purple brand palette, full light + dark variants, and a `BuildContext` extension that exposes the most-used semantic colors so widgets don't hard-code hex values.

## Brand palette — `AppColors`

```dart
class AppColors {
  static const purple       = Color(0xFFB05ECC);  // primary brand color
  static const purpleBright = Color(0xFFCE5DE5);  // accent / secondary
  static const purpleDeep   = Color(0xFF8A3FB8);
  static const purpleVivid  = Color(0xFF7E3BE8);  // button fill
  static const green        = Color(0xFF3BD671);
  static const red          = Color(0xFFE04E5C);
  static const orange       = Color(0xFFD27B2B);
}
```

`AppColors.purple` is THE brand color. `AppColors.purpleVivid` is the saturated CTA fill used by all primary buttons. `AppColors.purpleBright` is the dark-theme secondary.

## Theme objects

Two `ThemeData` instances exported as `AppTheme.light` and `AppTheme.dark`. Both use:

- `useMaterial3: true`
- `fontFamily: null` (system default)
- Identical `ButtonStyle`s for `FilledButton`, `OutlinedButton`, `TextButton` (defined once as `_primaryButtonStyle` / `_outlinedButtonStyle` / `_textButtonStyle`):
  - Pill-shaped (`BorderRadius.circular(30)`).
  - Bold 14sp (`FontWeight.w700`).
  - Filled buttons: purple `AppColors.purpleVivid` background, shadow tinted purple at 35% alpha.
  - Outlined: 1.4dp `purpleVivid` border.
- `inputDecorationTheme` — filled, rounded 14, no border, 16/14 padding.
- Custom `SwitchThemeData` so the OFF thumb stays visible on light surfaces (M3's default outline-thumb blends with the track).

### Light theme

| Field | Value |
|---|---|
| `brightness` | `Brightness.light` |
| `colorScheme.primary` | `AppColors.purple` (#B05ECC) |
| `colorScheme.secondary` | `AppColors.purpleBright` |
| `colorScheme.surface` | `Colors.white` |
| `colorScheme.onSurface` | `0xFF0F0F10` |
| `colorScheme.error` | `AppColors.red` |
| `colorScheme.outline` | `0xFFEDEDF2` |
| `colorScheme.surfaceContainerHighest` | `0xFFF0F0F0` |
| `scaffoldBackgroundColor` | `Colors.white` |
| `appBarTheme` | `Colors.white` bg, `Colors.black` fg, elevation 0 |
| `dividerColor` | `0xFFEDEDF2` |
| `cardColor` | `Colors.white` |
| `canvasColor` | `0xFFF7F6FB` |
| `hintColor` | `0xFFAAAAAA` |
| `iconTheme` | `0xFF6B6B70` |
| BottomNav selected / unselected | `AppColors.purple` / `0xFF6B6B70` |
| `inputDecorationTheme.fillColor` | `0xFFF0F0F0` |

### Dark theme

| Field | Value |
|---|---|
| `brightness` | `Brightness.dark` |
| `colorScheme.primary` | `AppColors.purple` |
| `colorScheme.secondary` | `AppColors.purpleBright` |
| `colorScheme.surface` | `0xFF1A1A1E` |
| `colorScheme.onSurface` | `0xFFE8E8EE` |
| `colorScheme.outline` | `0xFF2E2E34` |
| `colorScheme.surfaceContainerHighest` | `0xFF252528` |
| `scaffoldBackgroundColor` | `0xFF111114` |
| `appBarTheme` | `0xFF1A1A1E` bg, `0xFFE8E8EE` fg |
| `dividerColor` | `0xFF2E2E34` |
| `cardColor` | `0xFF1A1A1E` |
| `canvasColor` | `0xFF151518` |
| `hintColor` | `0xFF6B6B70` |
| `iconTheme` | `0xFF9B9BA0` |
| BottomNav selected / unselected | `AppColors.purpleBright` / `0xFF6B6B70` |
| `inputDecorationTheme.fillColor` | `0xFF252528` |

The light↔dark switch goes through [`themeModeProvider`](../../lib/src/providers/theme_provider.dart) — a `StateNotifierProvider<ThemeModeNotifier, ThemeMode>` backed by SharedPreferences key `isDarkMode`. Defaults to dark mode.

## `BuildContext` extensions — `ThemeX`

Defined at the bottom of [`app_theme.dart`](../../lib/src/theme/app_theme.dart). Use these everywhere instead of hard-coded colors so widgets follow the active theme:

```dart
extension ThemeX on BuildContext {
  ThemeData   get theme;
  ColorScheme get colors;
  bool        get isDark;

  // Common semantic colors
  Color get surfaceSoft;   // dark: 0xFF151518   light: 0xFFF7F6FB
  Color get inputFill;     // dark: 0xFF252528   light: 0xFFF0F0F0
  Color get cardBg;        // dark: 0xFF1A1A1E   light: Colors.white
  Color get borderColor;   // dark: 0xFF2E2E34   light: 0xFFEDEDF2
  Color get textPrimary;   // dark: 0xFFE8E8EE   light: 0xFF0F0F10
  Color get textSecondary; // dark: 0xFF9B9BA0   light: 0xFF6B6B70
  Color get textMuted;     // dark: 0xFF6B6B70   light: 0xFFAAAAAA
  Color get purpleSoft;    // dark: 0xFF2D1F3D   light: 0xFFF5E8FA  (chip backgrounds)
  Color get tagBg;         // dark: 0xFF3D2E1A   light: 0xFFFFF2E3  (tag backgrounds)
}
```

Used in virtually every screen and widget. Example usage:

```dart
Container(
  color: context.cardBg,
  child: Text('hi', style: TextStyle(color: context.textPrimary)),
)
```

## Shared layout widgets

### `AppPageBackground` — [`app_page_background.dart`](../../lib/src/features/widgets/app_page_background.dart)

Soft gradient background used by the main app tabs (Home, Events, Translate, Messages, Profile). Three diagonal stops:

- Dark: `[0xFF101017, 0xFF171726, 0xFF11111A]` (top-start → bottom-end).
- Light: `[0xFFF8F5FF, 0xFFEFF6FF, 0xFFFDF7F2]`.

Layered with three ambient `_AmbientGlow` radial gradients (blue-ish #6FA8FF, lavender #C08BFF, mint #6EE7B7) at 8-18% alpha — gives the background a subtle "aurora" feel without being distracting. Hosted by [`MainScreen`](../../lib/src/features/model/main_screen.dart) behind the `PageView`.

### `AppGlassCard` — same file

Reusable glassmorphism card. `BackdropFilter` + a translucent surface, soft outer shadow, optional purple emphasis glow.

- Surface alpha: 0.50 (dark) / 0.40 (light), overridable via `surfaceAlpha`.
- Border alpha: 0.14 (dark) / 0.45 (light), overridable via `borderAlpha`.
- Blur: 22px both axes.
- `emphasize: true` adds an extra `AppColors.purple`-tinted shadow at 20%/10%.

Used in: stories sheet, modals, settings cards, post compose, etc.

### Floating bottom nav

Drawn inline inside [`MainScreen`](../../lib/src/features/model/main_screen.dart) (NOT a separate widget file). A `Container` with `Colors.black.withValues(alpha: 0.3)`, `BorderRadius.circular(40)`, glass blur, and an `AnimatedPositionedDirectional` white circle bubble (34dp) that slides between the 5 tab slots. RTL-aware via `AnimatedPositionedDirectional.start`.

There's also a standalone [`BottomNav`](../../lib/src/features/widgets/botton_nav.dart) widget (note: filename misspelled `botton_nav.dart`) used by older / alternative flows.

## Common visual conventions

- Pill-shaped primary buttons everywhere (30dp radius).
- 14dp radius for inputs and most cards; 18dp for glass cards (`AppGlassCard.radius` default).
- 40dp radius for the floating nav.
- Purple brand glow on emphasis (used for unread badges, selected pills, the splash, etc.).
- Use `context.isDark` to branch on theme, not `Theme.of(context).brightness`.
- Use `AppColors.purple` for icons/highlights; `AppColors.purpleVivid` only for fills (it's saturated and reads harsh as a foreground).

## System UI (status bar / nav bar) handling

System chrome is configured in two places: at boot in [`main.dart`](../../lib/main.dart) `_configureSystemUi()`, and on every theme-change/rebuild via `MaterialApp.builder`.

### `_configureSystemUi({Brightness? appBrightness})` — `main.dart`

Called from `main()` BEFORE `runApp`. Sets:

- `statusBarColor: Colors.transparent`
- `statusBarIconBrightness` — light icons on dark themes, dark on light
- `statusBarBrightness` — opposite (iOS reads this one)
- `systemNavigationBarColor: Colors.transparent`
- `systemNavigationBarIconBrightness` — matches theme
- `systemNavigationBarDividerColor: Colors.transparent`

On Android, also calls `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`.

### Resume hook

In `_MyAppState.didChangeAppLifecycleState`, when the app resumes (`state == AppLifecycleState.resumed`), `_configureSystemUi` is called AGAIN with `appBrightness` matching the active theme. This fixes the brief flash where icons appeared invisible in dark mode after returning from background (the old code hardcoded `Brightness.light` and didn't reflect the user's current theme).

### `MaterialApp.builder` re-application

Every rebuild of the app shell re-applies `SystemChrome.setSystemUIOverlayStyle(...)` based on `Theme.of(context).brightness`. This keeps system chrome in sync as the user toggles dark mode without restarting.

## Locale-aware UI

`MaterialApp.locale` is driven by [`localeProvider`](../../lib/src/providers/locale_provider.dart). Changing it rebuilds the whole app, including `TextDirection` (LTR↔RTL) — see `05-localization.md`.

## Related files

- [`lib/src/theme/app_theme.dart`](../../lib/src/theme/app_theme.dart) — `AppColors`, `AppTheme.light`, `AppTheme.dark`, `extension ThemeX`.
- [`lib/src/providers/theme_provider.dart`](../../lib/src/providers/theme_provider.dart) — `themeModeProvider` + `sharedPreferencesProvider`.
- [`lib/src/features/widgets/app_page_background.dart`](../../lib/src/features/widgets/app_page_background.dart) — `AppPageBackground`, `AppGlassCard`.
- [`lib/src/features/widgets/botton_nav.dart`](../../lib/src/features/widgets/botton_nav.dart) — alternative standalone bottom nav.
- [`lib/src/features/model/main_screen.dart`](../../lib/src/features/model/main_screen.dart) — inline floating bottom nav + `AppPageBackground` host.
- [`lib/main.dart`](../../lib/main.dart) — `_configureSystemUi`, lifecycle resume hook, `MaterialApp.builder` SystemUI refresh.
