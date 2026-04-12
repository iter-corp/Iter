import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/model/main_screen.dart';
import '../features/screens/auth/forgot_password_screen.dart';
import '../features/screens/auth/login_screen.dart';
import '../features/screens/auth/onboarding_screen.dart';
import '../features/screens/auth/signup_screen.dart';
import '../features/screens/auth/splash_screen.dart';
import '../providers/auth_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final loc = state.matchedLocation;

      // While auth is loading, stay on splash.
      if (authAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final user = authAsync.value;
      final loggedIn = user != null;
      final inAuthFlow = loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password' ||
          loc == '/splash';

      if (!loggedIn) return inAuthFlow ? null : '/login';

      // Logged in — check if profile setup needed.
      final userDoc = ref.read(currentUserDocProvider).value;
      final needsOnboarding =
          userDoc != null && (userDoc['username'] == null);

      if (needsOnboarding && loc != '/onboarding') return '/onboarding';
      if (!needsOnboarding && (inAuthFlow || loc == '/onboarding')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/home', builder: (_, __) => const MainScreen()),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
    _ref.listen(currentUserDocProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}
