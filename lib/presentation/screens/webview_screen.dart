import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/repositories/push_notification_repo.dart';
import '../../data/services/webview_service.dart';

class WebViewScreen extends StatefulWidget {
  final VoidCallback? onReady;
  final void Function(bool connected)? onConnectivityChanged;

  const WebViewScreen({super.key, this.onReady, this.onConnectivityChanged});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewService _webViewService;
  late final WebViewController _controller;
  final PushNotificationRepository _pushRepo = PushNotificationRepository();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
    _initPushNotifications();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
    } else if (state == AppLifecycleState.paused) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (await _webViewService.canGoBack()) {
      await _webViewService.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canGoBack = await _webViewService.canGoBack();
        if (canGoBack) {
          await _webViewService.goBack();
        }
      },
      child: SafeArea(
        top: false,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
