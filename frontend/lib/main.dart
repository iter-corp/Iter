import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/providers/auth_providers.dart';
import 'src/router/app_router.dart';
import 'src/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[boot] WidgetsFlutterBinding ready');

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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
