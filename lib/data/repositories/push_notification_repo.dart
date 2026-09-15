import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationRepository {
  static final PushNotificationRepository _instance = PushNotificationRepository._();
  factory PushNotificationRepository() => _instance;
  PushNotificationRepository._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
  }

  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('[FCM] Token: ${token?.substring(0, 20)}...');
      return token;
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }

  Future<void> registerToken({String? uid}) async {
    final token = await getToken();
    if (token == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
    if (uid != null) {
      await prefs.setString('fcm_uid', uid);
    }
    debugPrint('[FCM] Token registered for uid=$uid');
  }

  Future<void> clearToken() async {
    try {
      await _messaging.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      await prefs.remove('fcm_uid');
      debugPrint('[FCM] Token cleared');
    } catch (e) {
      debugPrint('[FCM] clearToken error: $e');
    }
  }

  void onTokenRefresh(void Function(String token) callback) {
    _messaging.onTokenRefresh.listen(callback);
  }

  void setupForegroundNotificationHandling() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Message opened app: ${message.data}');
    });
  }
}
