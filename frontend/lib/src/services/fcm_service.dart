import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(uid, token);

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
    // After sign-out, Firestore writes are unauthenticated and will be denied.
    if (_auth.currentUser?.uid != uid) return;
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // Avoid crashing auth flow on transient permission/not-found races.
      if (e.code != 'permission-denied' && e.code != 'not-found') {
        rethrow;
      }
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    if (_auth.currentUser?.uid != uid) return;
    try {
      await _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // Avoid crashing auth flow on transient permission/not-found races.
      if (e.code != 'permission-denied' && e.code != 'not-found') {
        rethrow;
      }
    }
  }
}
