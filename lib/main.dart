import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'core/constants/app_constants.dart';
import 'core/network/network_service.dart';
import 'presentation/screens/webview_screen.dart';
import 'presentation/screens/no_internet_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('[boot] Firebase initialized');
  } catch (e) {
    debugPrint('[boot] Firebase init error: $e');
  }

  runApp(const IterApp());
}

class IterApp extends StatefulWidget {
  const IterApp({super.key});

  @override
  State<IterApp> createState() => _IterAppState();
}

class _IterAppState extends State<IterApp> {
  final NetworkService _networkService = NetworkService();
  bool _isConnected = true;
  bool _webViewReady = false;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub = _networkService.onConnectivityChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
    _networkService.checkConnectivity().then((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _onWebViewReady() {
    if (mounted) setState(() => _webViewReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9D4EDD),
          surface: Color(0xFF0B0E14),
        ),
      ),
      home: Stack(
        children: [
          WebViewScreen(
            onReady: _onWebViewReady,
            onConnectivityChanged: (connected) {
              if (mounted) setState(() => _isConnected = connected);
            },
          ),
          if (!_webViewReady) const _NativeSplash(),
          if (!_isConnected)
            NoInternetScreen(
              onRetry: () async {
                final connected = await _networkService.checkConnectivity();
                if (mounted) setState(() => _isConnected = connected);
              },
            ),
        ],
      ),
    );
  }
}

class _NativeSplash extends StatelessWidget {
  const _NativeSplash();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0E14),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9D4EDD).withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF9D4EDD),
                    child: const Icon(Icons.public, size: 48, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Iter',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9D4EDD)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
