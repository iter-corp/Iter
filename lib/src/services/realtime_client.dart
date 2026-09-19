import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

class RealtimeClient {
  RealtimeClient._();
  static final RealtimeClient instance = RealtimeClient._();

  WebSocketChannel? _channel;
  bool _connected = false;
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
    _disposed = false;
    if (_connected && _channel != null) return;
    if (_connecting) return;
    _connecting = true;

    try {
      final token = ApiClient.instance.accessToken;
      if (token == null || token.isEmpty) {
        _connecting = false;
        return;
      }

      final wsUrl = '${ApiClient.instance.wsUrl}?token=$token';
      debugPrint('[RealtimeClient] Connecting to $wsUrl');

      final uri = Uri.parse(wsUrl);
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 10));

      _channel = channel;
      _connected = true;
      debugPrint('[RealtimeClient] WebSocket connected successfully');

      _startHeartbeat();

      _channel!.stream.listen(
        (data) {
          try {
            final map = jsonDecode(data.toString()) as Map<String, dynamic>;
            _handleMessage(map);
          } catch (e) {
            debugPrint('[RealtimeClient] Parse error: $e');
          }
        },
        onDone: () => _handleDisconnect(),
        onError: (err) {
          debugPrint('[RealtimeClient] Error: $err');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[RealtimeClient] Connection failed: $e');
      _handleDisconnect();
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
      if (_connected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'heartbeat'}));
        } catch (_) {}
      }
    });
  }

  void _handleDisconnect() {
    _connected = false;
    _heartbeatTimer?.cancel();
    _channel = null;
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
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'typing',
          'payload': {
            'chatId': chatId,
            'isTyping': isTyping,
            'recipientUids': recipientUids,
          },
        }));
      } catch (_) {}
    }
  }

  void disconnect() {
    _disposed = true;
    _connected = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
