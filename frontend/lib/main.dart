import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/providers/auth_providers.dart';
import 'src/router/app_router.dart';
import 'src/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Init FCM once whenever a user signs in.
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
    );
  }
}
