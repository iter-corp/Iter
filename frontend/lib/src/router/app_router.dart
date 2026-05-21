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
import '../features/screens/language_screen.dart';
import '../providers/auth_providers.dart';
import '../services/error_report_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    // Tracks the current screen so error reports record where a crash happened.
    observers: [ErrorReportNavigatorObserver()],
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final loc = state.matchedLocation;

      // Show splash only on initial boot. During later auth refreshes, keep the
      // current route to avoid visible /home <-> /splash route churn.
      if (authAsync.isLoading) {
        return loc == '/splash' ? null : null;
      }

      final user = authAsync.value;
      final inAuthFlow = loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password' ||
          loc == '/otp';

      if (user == null) {
        // Not logged in - go to login unless already on auth page
        return inAuthFlow ? null : '/login';
      }

      // Logged in - check onboarding
      final userDocAsync = ref.read(currentUserDocProvider);

      // Keep current route while the user doc stream resolves; redirect once we
      // have a concrete value so we don't repeatedly reopen pages.
      if (userDocAsync.isLoading) {
        return null;
      }

      final authService = ref.read(authServiceProvider);

      final userDoc = userDocAsync.value;
      if (userDoc == null && authService.justSignedUp) {
        if (loc == '/onboarding' || loc == '/otp') return null;
        return '/onboarding';
      }

      final needsOnboarding =
          authService.justSignedUp && (userDoc?['username'] == null);

      if (needsOnboarding) {
        if (loc == '/onboarding' || loc == '/otp') return null;
        return '/onboarding';
      }

      // Onboarding done - send to home
      if (inAuthFlow || loc == '/onboarding' || loc == '/splash') {
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
        path: '/language',
        builder: (_, __) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardScreen(),
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  late final void Function()? _removeListener;
  bool _isDisposed = false;

  _AuthListenable(this._ref) {
    // Use select to only listen for specific value changes that matter for routing.
    // This prevents excessive notifications when intermediate loading states emit.
    _removeListener = _ref.listen(
      _routingStateSelector,
      (prev, next) {
        if (!_isDisposed) {
          // Only notify if the important values actually changed
          if (prev != next) {
            notifyListeners();
          }
        }
      },
    ).close;
  }

  final Ref _ref;

  // Selector that only emits when values that affect routing actually change
  static final _routingStateSelector = Provider((ref) {
    final authAsync = ref.watch(authStateProvider);
    final userDocAsync = ref.watch(currentUserDocProvider);
    final justSignedUp = ref.watch(
      Provider((r) => r.read(authServiceProvider).justSignedUp),
    );

    // Return a tuple of only the values that matter for routing decisions
    return (
      isAuthLoading: authAsync.isLoading,
      user: authAsync.value?.uid, // Only compare UIDs, not whole User objects
      isUserDocLoading: userDocAsync.isLoading,
      needsOnboarding: justSignedUp &&
          (userDocAsync.value == null ||
              userDocAsync.value!['username'] == null),
    );
  });

  @override
  void dispose() {
    _isDisposed = true;
    _removeListener?.call();
    super.dispose();
  }
}
