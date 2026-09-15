import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'api_client.dart';

class RealtimeClient {
  RealtimeClient._();
  static final RealtimeClient instance = RealtimeClient._();

  WebSocket? _ws;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _disposed = false;

  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect() async {
    if (_ws != null && _ws!.readyState == WebSocket.open) return;
    if (_connecting || _disposed) return;
    _connecting = true;

    try {
      final token = ApiClient.instance.accessToken;
      if (token == null || token.isEmpty) {
        _connecting = false;
        return;
      }

      final wsUrl = '${ApiClient.instance.wsUrl}?token=$token';
      debugPrint('[RealtimeClient] Connecting to $wsUrl');

      _ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
      debugPrint('[RealtimeClient] WebSocket connected successfully');

      _startHeartbeat();

      _ws!.listen(
        (data) {
          try {
            final map = jsonDecode(data.toString()) as Map<String, dynamic>;
            _handleMessage(map);
          } catch (e) {
            debugPrint('[RealtimeClient] Parse error: $e');
          }
        },
        onDone: () => _handleDisconnect(),
        onError: (err) => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[RealtimeClient] Connection failed: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'presence_update':
        _presenceController.add(msg);
        break;
      case 'typing_update':
        _typingController.add(msg);
        break;
      case 'new_message':
        _messageController.add(msg);
        break;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws != null && _ws!.readyState == WebSocket.open) {
        _ws!.add(jsonEncode({'type': 'heartbeat'}));
      }
    });
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _ws = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed && ApiClient.instance.isAuthenticated) {
        connect();
      }
    });
  }

  void setTyping({
    required String chatId,
    required bool isTyping,
    required List<String> recipientUids,
  }) {
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      _ws!.add(jsonEncode({
        'type': 'typing',
        'payload': {
          'chatId': chatId,
          'isTyping': isTyping,
          'recipientUids': recipientUids,
        },
      }));
    }
  }

  void disconnect() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _ws?.close();
    _ws = null;
  }
}
