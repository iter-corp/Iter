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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'src/features/widgets/event_detail.dart';
import 'src/features/widgets/event_unavailable_screen.dart';
import 'src/l10n/app_strings.dart';
import 'src/l10n/ckb_material_localizations.dart';
import 'src/providers/admin_providers.dart';
import 'src/providers/auth_providers.dart';
import 'src/providers/locale_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/router/app_router.dart';
import 'src/services/admin_service.dart';
import 'src/services/api_client.dart';
import 'src/services/error_report_service.dart';
import 'src/services/translate_service.dart';
import 'src/services/fcm_service.dart';
import 'src/services/message_cache.dart';
import 'src/services/presence_service.dart';
import 'src/theme/app_theme.dart';
import 'src/utils/responsive.dart';

String? _safeEnv(String key, {String? fallback}) {
  if (!dotenv.isInitialized) return fallback;
  try {
    return dotenv.maybeGet(key, fallback: fallback);
  } catch (_) {
    return fallback;
  }
}

Future<void> main() async {
  // Run the *entire* startup inside a guarded zone so uncaught async errors are
  // captured by the error reporter — and, crucially, so the binding is
  // initialized in the same zone that later calls `runApp` (Flutter asserts
  // these match). See https://docs.flutter.dev/testing/errors.
  ErrorReportService.instance.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (kIsWeb) {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) print(message);
      };
    }

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.exceptionAsString();
      if (msg.contains('assets/.env') ||
          msg.contains('EncodingError: The source image cannot be decoded') ||
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
      debugPrint('[boot] dotenv load failed (fallback to empty env): $e');
      try {
        dotenv.testLoad(fileInput: '');
      } catch (_) {}
    }

    try {
      await ApiClient.instance.init();
      debugPrint('[boot] ApiClient initialized');
    } catch (e) {
      debugPrint('[boot] ApiClient init non-fatal: $e');
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

    // Wire up app-wide error logging now that Firebase is up.
    try {
      ErrorReportService.instance.install();
    } catch (e) {
      debugPrint('[boot] ErrorReportService install non-fatal: $e');
    }

    try {
      final useEmulator =
          (_safeEnv('USE_FIREBASE_EMULATOR') ?? '').toLowerCase() == 'true';
      if (kDebugMode && useEmulator) {
        final host = _safeEnv('FIREBASE_EMULATOR_HOST') ?? 'localhost';
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
    } catch (e) {
      debugPrint('[boot] Emulator check non-fatal: $e');
    }

    // Start the API key store — listens to Firestore `apiKeys` collection so
    // TranslateService picks up keys added/disabled in the admin panel live.
    try {
      initApiKeyStore();
    } catch (e) {
      debugPrint('[boot] initApiKeyStore non-fatal: $e');
    }

    // One-time migration: seed existing .env keys into Firestore `apiKeys`
    try {
      unawaited(_seedApiKeysFromEnv());
    } catch (e) {
      debugPrint('[boot] _seedApiKeysFromEnv trigger non-fatal: $e');
    }

    // Sanity-check that auth stream produces a first event.
    try {
      FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[boot] authStateChanges timed out (no user / stuck)');
          return null;
        },
      ).then((u) => debugPrint('[boot] first auth event: ${u?.uid ?? 'null'}'));
    } catch (e) {
      debugPrint('[boot] authStateChanges listen non-fatal: $e');
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[boot] SharedPreferences init error: $e');
    }

    debugPrint('[boot] runApp');
    runApp(ProviderScope(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ));
  });
}

/// Seeds the existing .env API keys into Firestore `apiKeys` so the admin
/// API manager isn't empty on first launch. Only writes docs that don't
/// exist yet — completely safe to call on every boot.
Future<void> _seedApiKeysFromEnv() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.data()?['role'] != 'admin') return;

    final db = FirebaseFirestore.instance;
    final col = db.collection('apiKeys');

    final geminiKey = _safeEnv('GEMINI_API_KEY') ?? '';
    final azureKey1 = _safeEnv('AZURE_TRANSLATOR_KEY') ?? '';
    final azureKey2 = _safeEnv('AZURE_TRANSLATOR_KEY_2') ?? '';
    final seeds = [
      if (geminiKey.isNotEmpty)
        {'id': 'gemini_env', 'provider': 'gemini', 'key': geminiKey, 'priority': 0},
      if (azureKey1.isNotEmpty)
        {'id': 'azure_env', 'provider': 'azure', 'key': azureKey1, 'priority': 1},
      if (azureKey2.isNotEmpty)
        {'id': 'azure_env_2', 'provider': 'azure', 'key': azureKey2, 'priority': 2},
    ];

    for (final s in seeds) {
      final docId = s['id'] as String;
      final doc = col.doc(docId);
      final snap = await doc.get();
      final data = snap.data();
      if (!snap.exists) {
        // Create fresh.
        await doc.set({
          'provider': s['provider'],
          'key': s['key'],
          'active': true,
          'statusMessage': null,
          'lastChecked': null,
          'priority': s['priority'],
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('[boot] seeded apiKeys/$docId');
      } else if (data != null && !data.containsKey('priority')) {
        // Existing doc from before priority was added — patch it.
        await doc.update({'priority': s['priority']});
        debugPrint('[boot] patched priority on apiKeys/$docId');
      }
    }
  } catch (e) {
    debugPrint('[boot] _seedApiKeysFromEnv failed (non-fatal): $e');
  }
}

Future<void> _configureSystemUi({Brightness? appBrightness}) async {
  if (kIsWeb) return;

  // [appBrightness] picks the icon brightness so the status bar stays
  // legible against the app background. Defaults to light app
  // (= dark icons) for the very first paint before MaterialApp has a
  // theme; on lifecycle resume we pass the active theme brightness in.
  final isDark = appBrightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
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
  final PresenceService _presence = PresenceService();

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
      // Re-apply the overlay with the *current* theme brightness so the
      // status bar icons stay legible. The old call hardcoded light-mode
      // (dark icons) and briefly flashed invisible icons in dark mode
      // on resume before MaterialApp.builder corrected it.
      final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
      unawaited(_configureSystemUi(
        appBrightness: isDark ? Brightness.dark : Brightness.light,
      ));
      // Restore the "online" flag after returning from background. The
      // onDisconnect handler set in PresenceService.setOnline already
      // flips us back to offline if the socket drops, so we re-register
      // it here too.
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid != null) unawaited(_presence.setOnline(uid));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Mark offline as soon as the user backgrounds the app so other
      // people stop seeing them as "online" immediately, instead of
      // waiting for the RTDB onDisconnect to fire on socket close.
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid != null) unawaited(_presence.setOffline(uid));
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
          createdByUid: event.createdByUid,
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
        // Mark the user online from the moment they're signed in, so
        // their inbox tile and 1:1 chat headers show the green dot
        // even before they navigate into a specific chat.
        unawaited(_presence.setOnline(nextUser.uid));
      } else if (previousUser != null) {
        unawaited(fcmService.removeToken(previousUser.uid));
        unawaited(_presence.setOffline(previousUser.uid));
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
    final language = ref.watch(localeProvider);
    final minVersion =
        ref.watch(adminConfigProvider).valueOrNull?.minAppVersion ?? '';
    final isAdmin = ref.watch(isAdminProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // ── Localization ──────────────────────────────────────────
      // `locale` is driven by localeProvider; changing it rebuilds
      // the whole app, including text direction (LTR ↔ RTL), with
      // no restart needed.
      locale: language.locale,
      supportedLocales:
          AppLanguage.values.map((l) => l.locale).toList(growable: false),
      localizationsDelegates: const [
        // Kurdish Sorani (ckb) is not bundled with Flutter, so this
        // custom delegate maps it onto the Arabic Material/Cupertino
        // localizations (same RTL behavior, Arabic-script widgets).
        CkbMaterialLocalizations.delegate,
        CkbCupertinoLocalizations.delegate,
        CkbWidgetsLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
              isAdmin: isAdmin,
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
  final bool isAdmin;
  final Widget child;
  const _VersionGate({required this.minVersion, required this.isAdmin, required this.child});

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
    final requiresUpdate = !widget.isAdmin &&
        current != null &&
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
    return Scaffold(
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
                    context.t.updateRequiredTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t.updateRequiredBody(required, current),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
