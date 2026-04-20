import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'src/providers/admin_providers.dart';
import 'src/providers/auth_providers.dart';
import 'src/providers/theme_provider.dart';
import 'src/router/app_router.dart';
import 'src/services/fcm_service.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[boot] WidgetsFlutterBinding ready');
  await _configureSystemUi();

  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[boot] dotenv loaded');
  } catch (e) {
    debugPrint('[boot] dotenv load failed (ignored): $e');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[boot] Firebase initialized (fresh)');
  } catch (e) {
    debugPrint('[boot] Firebase init non-fatal: $e');
  }
  debugPrint('[boot] Firebase.apps=${Firebase.apps.length}');

  // Sanity-check that auth stream produces a first event.
  FirebaseAuth.instance.authStateChanges().first.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      debugPrint('[boot] authStateChanges timed out (no user / stuck)');
      return null;
    },
  ).then((u) => debugPrint('[boot] first auth event: ${u?.uid ?? 'null'}'));

  final prefs = await SharedPreferences.getInstance();
  debugPrint('[boot] runApp');
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MyApp(),
  ));
}

Future<void> _configureSystemUi() async {
  if (kIsWeb) return;

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_configureSystemUi());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      final previousUser = prev?.value;
      final nextUser = next.value;
      final fcmService = FcmService();

      if (nextUser != null) {
        unawaited(fcmService.init(nextUser.uid));
      } else if (previousUser != null) {
        unawaited(fcmService.removeToken(previousUser.uid));
      }
    });

    // If the user's Firestore profile transitions from present → missing
    // while they're signed in — e.g. an admin deletes them on another device
    // — sign them out so they can't keep using a ghost session. We require a
    // prior non-null value so the transient null that precedes the user-doc
    // write during a fresh sign-up doesn't log the user out immediately.
    // The cross-session admin-delete case is already handled by the blacklist
    // check inside authStateProvider.
    ref.listen<AsyncValue<Map<String, dynamic>?>>(currentUserDocProvider,
        (prev, next) {
      final authed = ref.read(authStateProvider).value != null;
      final wasPresent = prev?.value != null;
      final nowMissing = next.hasValue && next.value == null;
      if (authed && wasPresent && nowMissing) {
        unawaited(ref.read(authServiceProvider).signOut());
      }
    });

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Update system UI to match current theme.
        final isDark = Theme.of(context).brightness == Brightness.dark;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ));
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: _VersionGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// 📌 SECTION: Version Gate
//
// Blocks the app with an "Update required" screen when the installed version
// is below `adminConfig.minAppVersion`. Fails open: if the config hasn't
// loaded yet, or the version string can't be parsed, the app runs normally.
// ─────────────────────────────────────────────

class _VersionGate extends ConsumerStatefulWidget {
  final Widget child;
  const _VersionGate({required this.child});

  @override
  ConsumerState<_VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends ConsumerState<_VersionGate> {
  String? _currentVersion;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _currentVersion = info.version);
    }).catchError((_) {});
  }

  /// Returns negative if `a < b`, zero if equal, positive if `a > b`.
  /// Non-numeric or missing components are treated as 0.
  int _compareVersions(String a, String b) {
    List<int> parts(String s) => s
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final aa = parts(a);
    final bb = parts(b);
    final len = aa.length > bb.length ? aa.length : bb.length;
    for (var i = 0; i < len; i++) {
      final av = i < aa.length ? aa[i] : 0;
      final bv = i < bb.length ? bb[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(adminConfigProvider).valueOrNull;
    final minVersion = cfg?.minAppVersion ?? '';
    final current = _currentVersion;
    if (current != null &&
        minVersion.isNotEmpty &&
        _compareVersions(current, minVersion) < 0) {
      return _UpdateRequiredScreen(current: current, required: minVersion);
    }
    return widget.child;
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  final String current;
  final String required;

  const _UpdateRequiredScreen({required this.current, required this.required});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update_outlined,
                      size: 64, color: Color(0xFFB05ECC)),
                  const SizedBox(height: 16),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please update to version $required or newer to continue. '
                    'You are on version $current.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
