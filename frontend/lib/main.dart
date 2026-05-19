import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'src/features/widgets/event_detail.dart';
import 'src/features/widgets/event_unavailable_screen.dart';
import 'src/providers/admin_providers.dart';
import 'src/providers/auth_providers.dart';
import 'src/providers/theme_provider.dart';
import 'src/router/app_router.dart';
import 'src/services/admin_service.dart';
import 'src/services/error_report_service.dart';
import 'src/services/fcm_service.dart';
import 'src/services/message_cache.dart';
import 'src/theme/app_theme.dart';
import 'src/utils/responsive.dart';

Future<void> main() async {
  // Run the *entire* startup inside a guarded zone so uncaught async errors are
  // captured by the error reporter — and, crucially, so the binding is
  // initialized in the same zone that later calls `runApp` (Flutter asserts
  // these match). See https://docs.flutter.dev/testing/errors.
  ErrorReportService.instance.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details
              .exceptionAsString()
              .contains('EncodingError: The source image cannot be decoded') ||
          details.library == 'image resource service') {
        return;
      }
      if (originalOnError != null) {
        originalOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

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

    // Wire up app-wide error logging now that Firebase is up. This chains onto
    // the FlutterError.onError handler installed above and adds a platform-error
    // hook, forwarding errors to the `errorReports` collection (rate-limited).
    ErrorReportService.instance.install();

    // Connect to emulators only when explicitly enabled. On a real device,
    // 'localhost' resolves to the phone itself, so leaving this on caused
    // every callable/Firestore call to hang. Set USE_FIREBASE_EMULATOR=true
    // in .env to re-enable, and set FIREBASE_EMULATOR_HOST to your PC's LAN
    // IP (e.g. 192.168.1.42) when testing on a physical device.
    final useEmulator =
        (dotenv.maybeGet('USE_FIREBASE_EMULATOR') ?? '').toLowerCase() ==
            'true';
    if (kDebugMode && useEmulator) {
      final host = dotenv.maybeGet('FIREBASE_EMULATOR_HOST') ?? 'localhost';
      try {
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
        FirebaseStorage.instance.useStorageEmulator(host, 9199);
        FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
        debugPrint('[boot] Connected to Firebase emulators @ $host');
      } catch (e) {
        debugPrint('[boot] Emulator connection failed: $e');
      }
    }

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
  });
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
  late final StreamSubscription<FcmMessageEvent> _fcmTapSubscription;
  final Set<String> _handledFcmMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fcmTapSubscription = FcmService().events.listen(_handleFcmEvent);
  }

  @override
  void dispose() {
    _fcmTapSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_configureSystemUi());
    }
  }

  void _handleFcmEvent(FcmMessageEvent event) {
    if (!event.openedApp || !mounted) return;

    final messageId = event.message.messageId;
    if (messageId != null && !_handledFcmMessageIds.add(messageId)) {
      return;
    }

    final data = event.message.data;
    final type = data['type']?.trim();
    final targetId = data['targetId']?.trim();
    if (type == 'new_event' && targetId != null && targetId.isNotEmpty) {
      unawaited(_openEventDetailFromPush(targetId));
    }
  }

  Future<void> _openEventDetailFromPush(String eventId) async {
    final snap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .get();
    if (!mounted) return;

    if (!snap.exists) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EventUnavailableScreen()),
      );
      return;
    }

    final event = AdminEvent.fromDoc(snap);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          title: event.title,
          subtitle: event.subtitle,
          location: event.location,
          eventType: event.eventType,
          funds: event.funds,
          deadlineAt: event.deadlineAt,
          imageUrls: event.imageUrls,
          description: event.description,
          link: event.link,
          phone: event.phone,
          email: event.email,
        ),
      ),
    );
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
        // Wipe the on-disk message cache so the next user on this
        // device can't see plaintext previews from the signed-out
        // account.
        unawaited(MessageCache.instance.clearAll());
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
    final minVersion =
        ref.watch(adminConfigProvider).valueOrNull?.minAppVersion ?? '';
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
        return ResponsiveBootstrap(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: _VersionGate(
              minVersion: minVersion,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
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

class _VersionGate extends StatefulWidget {
  final String minVersion;
  final Widget child;
  const _VersionGate({required this.minVersion, required this.child});

  @override
  State<_VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<_VersionGate> {
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
    final minVersion = widget.minVersion;
    final current = _currentVersion;
    final requiresUpdate = current != null &&
        minVersion.isNotEmpty &&
        _compareVersions(current, minVersion) < 0;

    if (!requiresUpdate) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: _UpdateRequiredScreen(current: current, required: minVersion),
        ),
      ],
    );
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
