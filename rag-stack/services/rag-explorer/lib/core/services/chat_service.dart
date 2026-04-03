import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/response_message.dart';
import '../models/session.dart';
import '../../features/settings/settings_page.dart';

final chatServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  return ChatService(Dio(), config);
});

class ChatService {
  final Dio _dio;
  final AppConfig _config;
  ChatService(this._dio, this._config);

  Future<List<Session>> getSessions() async {
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/memory/sessions');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => Session.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching sessions: $e');
      return [];
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    try {
      final response = await _dio.delete('${_config.ragAdminApiUrl}/api/memory/sessions/$sessionId');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('Error deleting session: $e');
      return false;
    }
  }

  Future<List<ResponseMessage>> getMessages(String sessionId) async {
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/db/sessions/$sessionId/messages');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) {
          return ResponseMessage(
            content: e['content'],
            role: e['role'],
            timestamp: DateTime.parse(e['timestamp']),
          );
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  Stream<ResponseMessage> streamChat({
    required String prompt,
    required String sessionId,
    required String planner,
    required String executor,
    required List<String> tags,
  }) {
    // Construct the WebSocket URL via the rag-admin-api proxy
    final uri = Uri.parse(_config.ragAdminApiUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = (uri.port != 0 && ((uri.scheme == 'https' && uri.port != 443) || (uri.scheme == 'http' && uri.port != 80))) ? ':${uri.port}' : '';
    final wsUrl = '$wsScheme://${uri.host}$portPart/api/chat/v1/rag/chat/stream';

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
