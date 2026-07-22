import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

class PoseWebSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({
    required String userExerciseId,
    required String token,
  }) async {
    await disconnect();

    final uri = Uri.parse(
      '${ApiConfig.webSocketBaseUrl}/ws/pose/'
      '$userExerciseId'
      '?token=${Uri.encodeQueryComponent(token)}',
    );

    final channel = WebSocketChannel.connect(uri);

    await channel.ready.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('WebSocket ket noi qua 15 giay.');
      },
    );

    _channel = channel;

    _subscription = channel.stream.listen(
      (rawMessage) {
        try {
          final decoded = rawMessage is String
              ? jsonDecode(rawMessage)
              : jsonDecode(utf8.decode(rawMessage as List<int>));

          if (decoded is Map<String, dynamic>) {
            _messageController.add(decoded);
          } else {
            _messageController.add({
              'event': 'unknown',
              'data': decoded,
            });
          }
        } catch (error) {
          _messageController.add({
            'event': 'decode_error',
            'error': error.toString(),
            'raw': rawMessage.toString(),
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _messageController.add({
          'event': 'socket_error',
          'error': error.toString(),
        });
      },
      onDone: () {
        _messageController.add({
          'event': 'socket_closed',
        });
        _channel = null;
      },
    );
  }

  void sendFrame(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('WebSocket chua ket noi.');
    }
    channel.sink.add(jsonEncode({'type': 'frame', ...frame}));
  }

  void sendDone() {
    final channel = _channel;
    if (channel == null) {
      throw StateError('WebSocket chua ket noi.');
    }
    channel.sink.add(jsonEncode({'type': 'done'}));
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;

    final channel = _channel;
    _channel = null;

    if (channel != null) {
      await channel.sink.close(status.normalClosure);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
  }
}
