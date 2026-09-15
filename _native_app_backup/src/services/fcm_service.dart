import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'api_client.dart';

// ─────────────────────────────────────────────
// Background message handler (top-level, not a class method)
// ─────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

class FcmMessageEvent {
  final RemoteMessage message;
  final bool openedApp;

  const FcmMessageEvent({
    required this.message,
    required this.openedApp,
  });
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final StreamController<FcmMessageEvent> _eventsController =
      StreamController<FcmMessageEvent>.broadcast();
  static bool _listenersRegistered = false;

  Stream<FcmMessageEvent> get events => _eventsController.stream;

  /// Call once after sign-in to request permission, persist the device token,
  /// and register listeners.
  Future<void> init(String uid) async {
    // Register background handler before any other FCM code (native only).
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    }

    // Request OS notification permission (iOS, Android 13+, web).
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Persist the current token. Skip on web (needs VAPID key separately).
    if (!kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        String? apns;
        for (var i = 0; i < 10; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) {
          _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
          return;
        }
      }

      try {
        final token = await _messaging.getToken();
        if (token != null) await _saveToken(uid, token);
      } catch (_) {
        // Transient FCM error — let onTokenRefresh recover.
      }

      _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    }

    if (!_listenersRegistered) {
      _listenersRegistered = true;
      FirebaseMessaging.onMessage.listen((message) {
        _eventsController.add(
          FcmMessageEvent(message: message, openedApp: false),
        );
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _eventsController.add(
          FcmMessageEvent(message: message, openedApp: true),
        );
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _eventsController.add(
          FcmMessageEvent(message: initialMessage, openedApp: true),
        );
      }
    }
  }

  /// Remove this device's token when the user signs out.
  Future<void> removeToken(String uid) async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await ApiClient.instance.delete('/notifications/fcm-token', body: {'token': token});
    } catch (_) {
      // No token to remove — ignore.
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      final deviceType = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : (defaultTargetPlatform == TargetPlatform.android ? 'android' : 'web');
      await ApiClient.instance.post('/notifications/fcm-token', body: {
        'token': token,
        'deviceType': deviceType,
      });
    } catch (_) {}
  }
}
