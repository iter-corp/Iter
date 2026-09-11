import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final dynamic details;

  ApiException({
    required this.message,
    required this.statusCode,
    this.code,
    this.details,
  });

  @override
  String toString() => 'ApiException [$statusCode ${code ?? ""}]: $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String _accessTokenKey = 'iter_access_token';
  static const String _refreshTokenKey = 'iter_refresh_token';
  static const String _userIdKey = 'iter_user_id';
  static const String _userEmailKey = 'iter_user_email';

  String? _accessToken;
  String? _refreshToken;
  String? _currentUserId;
  String? _currentUserEmail;
  bool _initialized = false;
  final http.Client _client = http.Client();

  /// Default API base URL. Can be overridden in `.env` as `API_BASE_URL`.
  /// Uses loopback alias for Android emulator (10.0.2.2) if on Android.
  String get baseUrl {
    if (dotenv.isInitialized) {
      final envUrl = dotenv.env['API_BASE_URL']?.trim();
      if (envUrl != null && envUrl.isNotEmpty) {
        return envUrl.replaceAll(RegExp(r'/+$'), '');
      }
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        final port = Uri.base.hasPort ? ':${Uri.base.port}' : '';
        return '${Uri.base.scheme}://$host$port/api/v1';
      }
      return 'https://iterglobal.icu/api/v1';
    }

    if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api/v1';
    }

    return 'https://iterglobal.icu/api/v1';
  }

  /// WebSocket URL for realtime presence and chat
  String get wsUrl {
    final httpBase = baseUrl;
    final wsBase = httpBase.startsWith('https://')
        ? httpBase.replaceFirst('https://', 'wss://')
        : httpBase.replaceFirst('http://', 'ws://');
    return wsBase.replaceAll('/api/v1', '/ws');
  }

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _currentUserId = prefs.getString(_userIdKey);
    _currentUserEmail = prefs.getString(_userEmailKey);
    _initialized = true;
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get currentUserId => _currentUserId;
  String? get currentUserEmail => _currentUserEmail;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
    String? userEmail,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (userId != null) _currentUserId = userId;
    if (userEmail != null) _currentUserEmail = userEmail;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (_currentUserId != null) await prefs.setString(_userIdKey, _currentUserId!);
    if (_currentUserEmail != null) await prefs.setString(_userEmailKey, _currentUserEmail!);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUserId = null;
    _currentUserEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
  }

  Map<String, String> _buildHeaders({Map<String, String>? extraHeaders}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }

    return headers;
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParams, Map<String, String>? headers}) async {
    return _sendWithRetry(() async {
      final uri = _resolveUri(path, queryParams);
      final res = await _client.get(uri, headers: _buildHeaders(extraHeaders: headers));
      return _handleResponse(res);
    });
  }

  Future<dynamic> post(String path, {dynamic body, Map<String, String>? headers}) async {
    return _sendWithRetry(() async {
      final uri = _resolveUri(path);
      final res = await _client.post(
        uri,
        headers: _buildHeaders(extraHeaders: headers),
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(res);
    });
  }

  Future<dynamic> patch(String path, {dynamic body, Map<String, String>? headers}) async {
    return _sendWithRetry(() async {
      final uri = _resolveUri(path);
      final res = await _client.patch(
        uri,
        headers: _buildHeaders(extraHeaders: headers),
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(res);
    });
  }

  Future<dynamic> put(String path, {dynamic body, Map<String, String>? headers}) async {
    return _sendWithRetry(() async {
      final uri = _resolveUri(path);
      final res = await _client.put(
        uri,
        headers: _buildHeaders(extraHeaders: headers),
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(res);
    });
  }

  Future<dynamic> delete(String path, {dynamic body, Map<String, String>? headers}) async {
    return _sendWithRetry(() async {
      final uri = _resolveUri(path);
      final res = await _client.delete(
        uri,
        headers: _buildHeaders(extraHeaders: headers),
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(res);
    });
  }

  /// Automatic 401 token refresh interceptor
  Future<T> _sendWithRetry<T>(Future<T> Function() request) async {
    await init();
    try {
      return await request();
    } on ApiException catch (e) {
      if (e.statusCode == 401 && _refreshToken != null && _refreshToken!.isNotEmpty) {
        final refreshed = await _attemptTokenRefresh();
        if (refreshed) {
          return await request();
        }
      }
      rethrow;
    }
  }

  Future<bool> _attemptTokenRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final refreshUri = Uri.parse('$baseUrl/auth/refresh');
      final res = await _client.post(
        refreshUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tokens = data['data']['tokens'];
        await setTokens(
          accessToken: tokens['accessToken'],
          refreshToken: tokens['refreshToken'],
        );
        return true;
      } else {
        await clearTokens();
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  Uri _resolveUri(String path, [Map<String, String>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    final uri = Uri.parse(fullUrl);
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: {...uri.queryParameters, ...queryParams});
    }
    return uri;
  }

  dynamic _handleResponse(http.Response res) {
    dynamic jsonBody;
    try {
      jsonBody = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    } catch (_) {
      jsonBody = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (jsonBody is Map<String, dynamic> && jsonBody.containsKey('data')) {
        return jsonBody['data'];
      }
      return jsonBody;
    }

    String errorMessage = 'Request failed with status ${res.statusCode}';
    String? errorCode;
    dynamic details;

    if (jsonBody is Map<String, dynamic>) {
      final err = jsonBody['error'];
      if (err is Map<String, dynamic>) {
        errorMessage = (err['message'] ?? jsonBody['message'] ?? 'Request failed').toString();
        errorCode = err['code']?.toString();
        details = err['details'];
      } else if (jsonBody['message'] != null) {
        errorMessage = jsonBody['message'].toString();
      }
    }

    throw ApiException(
      message: errorMessage.toString(),
      statusCode: res.statusCode,
      code: errorCode?.toString(),
      details: details,
    );
  }
}
