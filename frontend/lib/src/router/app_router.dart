import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/model/main_screen.dart';
import '../features/screens/admin/admin_dashboard_screen.dart';
import '../features/screens/auth/forgot_password_screen.dart';
import '../features/screens/auth/login_screen.dart';
import '../features/screens/auth/onboarding_screen.dart';
import '../features/screens/auth/otp_screen.dart';
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

      // While auth is loading, show the splash screen.
      if (authAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final user = authAsync.value;
      final loggedIn = user != null;
      // Auth flow pages (explicit login/signup/forgot). Do NOT include splash
      // so that once loading finishes unauthenticated users are forwarded to
      // the login page instead of remaining on splash.
      final inAuthFlow = loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password' ||
          loc == '/otp';

      if (!loggedIn) {
        // If the user isn't logged in, send them to login unless they're
        // already on an auth page.
        return inAuthFlow ? null : '/login';
      }

      // Logged in — check if profile setup needed.
      final userDocAsync = ref.read(currentUserDocProvider);
      final userDoc = userDocAsync.value;

      // While user doc is still loading (first emission hasn't happened yet),
      // keep showing the splash instead of bouncing them to /home with no
      // knowledge of onboarding state.
      if (userDocAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final needsOnboarding = userDoc != null && (userDoc['username'] == null);

      if (needsOnboarding && loc != '/onboarding' && loc != '/otp') {
        return '/onboarding';
      }
      // Anywhere we're still on the splash or in auth flow, move to home.
      if (!needsOnboarding &&
          (inAuthFlow || loc == '/onboarding' || loc == '/splash')) {
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
        path: '/otp',
        builder: (_, state) => OtpScreen(
          email: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/home', builder: (_, __) => const MainScreen()),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardScreen(),
      ),
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
