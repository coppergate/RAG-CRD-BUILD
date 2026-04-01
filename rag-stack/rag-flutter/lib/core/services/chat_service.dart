import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/response_message.dart';
import '../../config/service_endpoints.dart';

final chatServiceProvider = Provider((ref) => ChatService());

class ChatService {
  Stream<ResponseMessage> streamChat({
    required String prompt,
    required String sessionId,
    required String planner,
    required String executor,
    required List<String> tags,
  }) {
    // Construct the WebSocket URL via the rag-admin-api proxy
    final uri = Uri.parse(ServiceEndpoints.ragAdminApi);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final wsUrl = '$wsScheme://${uri.host}${uri.port != 0 ? ':${uri.port}' : ''}/api/chat/v1/rag/chat/stream';

    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    final request = {
      'prompt': prompt,
      'session_id': sessionId,
      'planner': planner,
      'executor': executor,
      'tags': tags,
    };

    channel.sink.add(jsonEncode(request));

    return channel.stream.map((event) {
      final data = jsonDecode(event);
      return ResponseMessage(
        content: data['chunk'] ?? '',
        sessionId: data['session_id'],
        messageId: data['id'],
        role: 'assistant',
        metadata: data['metadata'] ?? {},
        timestamp: DateTime.now(),
      );
    });
  }
}
