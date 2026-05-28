import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Lightweight, app-wide error logging.
///
/// Captured errors (uncaught Flutter framework errors, zone errors, and any
/// errors reported manually via [report]) are written to the `errorReports`
/// Firestore collection so admins can review them in the dashboard. This is a
/// minimal substitute for a full crash-reporting SDK — it intentionally
/// rate-limits writes so a tight error loop can't run up Firestore costs.
class ErrorReportService {
  ErrorReportService._();
  static final ErrorReportService instance = ErrorReportService._();

  // Resolved lazily — the singleton is touched in `main()` *before*
  // Firebase.initializeApp(), so we must not grab Firestore in the ctor.
  FirebaseFirestore? _dbInstance;
  FirebaseFirestore? get _db {
    if (_dbInstance != null) return _dbInstance;
    if (Firebase.apps.isEmpty) return null;
    return _dbInstance = FirebaseFirestore.instance;
  }

  static const _maxPerSession = 25;
  static const _minGap = Duration(seconds: 3);

  int _sentThisSession = 0;
  DateTime? _lastSentAt;
  String? _appVersion;
  // De-dupe identical messages within a short window so one repeated error
  // doesn't flood the collection.
  final Map<String, DateTime> _recentSignatures = {};

  /// The screen the user is currently on, attached to every error report.
  /// Updated by [ErrorReportNavigatorObserver] (route name / widget type) and
  /// can be overridden manually via [setCurrentScreen].
  String _currentScreen = 'unknown';
  String get currentScreen => _currentScreen;

  /// Lets a screen explicitly label itself (useful for screens pushed by
  /// GoRouter or with no route name). Pass null to clear.
  void setCurrentScreen(String? screen) {
    final s = (screen ?? '').trim();
    if (s.isNotEmpty) _currentScreen = s;
  }

  /// Internal: called by the navigator observer when the top route changes.
  void _onTopRouteChanged(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name?.trim();
    if (name != null && name.isNotEmpty) {
      _currentScreen = name;
      return;
    }
    // Unnamed (e.g. MaterialPageRoute(builder: ...)) — try to name it by the
    // widget the route builds. We can't peek the builder directly, so fall
    // back to the route's own runtimeType as a coarse label.
    _currentScreen = route.runtimeType.toString();
  }

  /// Wires up global error handlers. Call once early in `main()` — but *after*
  /// Firebase has been initialized. [runApp] should be invoked inside [zoneBody]
  /// (see `main.dart`) so zone errors are captured too.
  void install() {
    unawaited(PackageInfo.fromPlatform().then(
      (i) => _appVersion = i.version,
      onError: (_) {},
    ));

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Keep whatever the app already does (it filters image-decode noise).
      previousOnError?.call(details);
      report(
        details.exception,
        details.stack,
        context: details.context?.toString(),
        kind: 'flutter',
      );
    };

    // Errors that escape to the platform (e.g. in async callbacks not inside
    // the zone). Returning true marks them handled for our purposes.
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, kind: 'platform');
      return true;
    };
  }

  /// Run [body] inside a guarded zone so uncaught async errors are reported.
  ///
  /// [body] may be `async`; the zone outlives it, so errors thrown after it
  /// returns (in timers, futures, etc.) are still caught. The Flutter binding
  /// should be initialized *inside* [body] so it lives in this same zone.
  void runGuarded(FutureOr<void> Function() body) {
    runZonedGuarded<void>(
      () => body(),
      (error, stack) => report(error, stack, kind: 'zone'),
    );
  }

  /// Manually log a handled error (e.g. inside a `catch`) so it shows up in the
  /// admin dashboard. Best-effort and silent on failure.
  Future<void> report(
    Object error,
    StackTrace? stack, {
    String? context,
    String? kind,
    String? screen,
  }) async {
    try {
      final message = error.toString();
      final signature = '${kind ?? ''}|${message.split('\n').first}';

      final now = DateTime.now();
      _recentSignatures.removeWhere(
        (_, t) => now.difference(t) > const Duration(minutes: 2),
      );
      if (_recentSignatures.containsKey(signature)) return;
      if (_sentThisSession >= _maxPerSession) return;
      if (_lastSentAt != null && now.difference(_lastSentAt!) < _minGap) return;

      final db = _db;
      if (db == null) return; // Firebase not initialized yet — skip.

      _recentSignatures[signature] = now;
      _lastSentAt = now;
      _sentThisSession++;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final stackStr = (stack ?? StackTrace.current).toString();
      // Use the explicitly-passed screen if any, otherwise whatever the
      // navigator observer last recorded.
      final screenName = (screen != null && screen.trim().isNotEmpty)
          ? screen.trim()
          : _currentScreen;
      await db.collection('errorReports').add({
        'message': message,
        // Cap the stack so a giant trace doesn't bloat the doc.
        'stack': stackStr.length > 6000 ? stackStr.substring(0, 6000) : stackStr,
        'kind': kind ?? 'manual',
        if (context != null && context.isNotEmpty) 'context': context,
        if (screenName.isNotEmpty) 'screen': screenName,
        'uid': uid,
        'platform': defaultTargetPlatform.name,
        'appVersion': _appVersion ?? '',
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Never let the error reporter itself crash the app.
    }
  }
}

/// Add to `MaterialApp.router(observers: [...])` (or any Navigator) so the
/// error reporter always knows which screen the user is on when an error fires.
class ErrorReportNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ErrorReportService.instance._onTopRouteChanged(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ErrorReportService.instance._onTopRouteChanged(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    ErrorReportService.instance._onTopRouteChanged(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ErrorReportService.instance._onTopRouteChanged(previousRoute);
    super.didRemove(route, previousRoute);
  }
}

// ─────────────────────────────────────────────
// Admin-side reading / management
// ─────────────────────────────────────────────

class ErrorReport {
  final String id;
  final String message;
  final String stack;
  final String kind;
  final String? context;
  final String? screen;
  final String? uid;
  final String platform;
  final String appVersion;
  final bool resolved;
  final DateTime? createdAt;

  const ErrorReport({
    required this.id,
    required this.message,
    required this.stack,
    required this.kind,
    required this.context,
    required this.screen,
    required this.uid,
    required this.platform,
    required this.appVersion,
    required this.resolved,
    required this.createdAt,
  });

  factory ErrorReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ErrorReport(
      id: doc.id,
      message: (d['message'] as String?) ?? '',
      stack: (d['stack'] as String?) ?? '',
      kind: (d['kind'] as String?) ?? 'unknown',
      context: d['context'] as String?,
      screen: d['screen'] as String?,
      uid: d['uid'] as String?,
      platform: (d['platform'] as String?) ?? '',
      appVersion: (d['appVersion'] as String?) ?? '',
      resolved: (d['resolved'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class ErrorReportAdmin {
  final _db = FirebaseFirestore.instance;

  Stream<List<ErrorReport>> stream({int limit = 200}) => _db
      .collection('errorReports')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(ErrorReport.fromDoc).toList());

  Future<void> setResolved(String id, bool resolved) =>
      _db.collection('errorReports').doc(id).update({'resolved': resolved});

  Future<void> delete(String id) =>
      _db.collection('errorReports').doc(id).delete();

  /// Bulk-clear all reports already marked resolved.
  Future<int> clearResolved() async {
    final snap = await _db
        .collection('errorReports')
        .where('resolved', isEqualTo: true)
        .limit(400)
        .get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    return snap.docs.length;
  }
}
