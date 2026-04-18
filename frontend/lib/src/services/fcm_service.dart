import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ─────────────────────────────────────────────
// Background message handler (top-level, not a class method)
// ─────────────────────────────────────────────

/// Must be a top-level function annotated vm:entry-point.
/// The OS shows the notification payload automatically; no extra work needed.
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
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
      // On iOS/macOS, getToken() fails unless the APNS token is already set by
      // the OS. On first launch (and occasionally on cold start) APNS registration
      // hasn't completed yet, so poll briefly before giving up.
      if (Platform.isIOS || Platform.isMacOS) {
        String? apns;
        for (var i = 0; i < 10; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) {
          // No APNS token (e.g. simulator, permission denied, no provisioning).
          // Skip FCM token fetch this session; onTokenRefresh will fire later.
          _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
          return;
        }
      }

      try {
        final token = await _messaging.getToken();
        if (token != null) await _saveToken(uid, token);
      } catch (_) {
        // APNS token race or transient FCM error — let onTokenRefresh recover.
      }

      // Keep the token fresh across app restarts.
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

  /// Remove this device's token when the user signs out so no stale
  /// push notifications are delivered.
  Future<void> removeToken(String uid) async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _db.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {
      // No APNS/FCM token to remove — ignore.
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }
}
