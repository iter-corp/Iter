import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/providers/auth_providers.dart';
import 'src/router/app_router.dart';
import 'src/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[boot] WidgetsFlutterBinding ready');
  await _configureAndroidSystemUi();

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

  debugPrint('[boot] runApp');
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _configureAndroidSystemUi() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      unawaited(_configureAndroidSystemUi());
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
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
    );
  }
}
