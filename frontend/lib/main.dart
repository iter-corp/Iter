import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
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
          child: child,
        );
      },
    );
  }
}
