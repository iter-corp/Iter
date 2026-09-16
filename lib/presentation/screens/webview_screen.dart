import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/repositories/push_notification_repo.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/webview_service.dart';

class WebViewScreen extends StatefulWidget {
  final VoidCallback? onReady;
  final void Function(bool connected)? onConnectivityChanged;

  const WebViewScreen({super.key, this.onReady, this.onConnectivityChanged});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewService _webViewService;
  late final WebViewController _controller;
  final PushNotificationRepository _pushRepo = PushNotificationRepository();
  bool _initialized = false;
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await PermissionService.requestStartupPermissions();
    await _initPushNotifications();
  }

  void _initWebView() {
    _webViewService = WebViewService(
      onReady: () {
        if (!_initialized) {
          _initialized = true;
          widget.onReady?.call();
        }
      },
    );
    _controller = _webViewService.initialize();
  }

  Future<void> _initPushNotifications() async {
    await _pushRepo.requestPermission();
    await _pushRepo.getToken();
    _pushRepo.setupForegroundNotificationHandling();
    _pushRepo.onTokenRefresh((token) {
      debugPrint('[FCM] Token refreshed');
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // Check if currently on a root screen
        final currentUrl = await _controller.currentUrl() ?? '';
        final uri = Uri.tryParse(currentUrl);
        final fragment = uri?.fragment ?? '';

        final isRootScreen = fragment.isEmpty ||
            fragment == '/' ||
            fragment == '/home' ||
            fragment == '/splash' ||
            fragment == '/login';

        final canGoBack = await _webViewService.canGoBack();

        // 1. If on an inner page and has history, go back inside WebView
        if (canGoBack && !isRootScreen) {
          await _webViewService.goBack();
          return;
        }

        // 2. On root screen: double-tap back within 2 seconds to exit app
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          if (context.mounted) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF9D4EDD), size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Press back again to exit',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF181D2A),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: const Color(0xFF9D4EDD).withValues(alpha: 0.3),
                  ),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: SafeArea(
          top: true,
          bottom: true,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
