import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:rag_explorer/config/app_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/response_message.dart';
import '../models/session.dart';
import '../../features/settings/settings_page.dart';
import 'log_service.dart';

final chatServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final logNotifier = ref.watch(logProvider.notifier);
  return ChatService(Dio(), config, logNotifier);
});

class ChatService {
  final Dio _dio;
  final AppConfig _config;
  final LogNotifier _logger;
  ChatService(this._dio, this._config, this._logger);

  Future<List<Session>> getSessions() async {
    _logger.debug('Fetching sessions from ${_config.ragAdminApiUrl}/api/memory/sessions');
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/memory/sessions');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _logger.info('Successfully fetched ${data.length} sessions');
        return data.map((e) => Session.fromJson(e)).toList();
      }
      _logger.warn('Failed to fetch sessions, status: ${response.statusCode}');
      return [];
    } catch (e) {
      _logger.error('Error fetching sessions: $e');
      return [];
    }
  }

  Future<Session?> createSession(String id, String name) async {
    _logger.info('Creating session: $name (id: $id)');
    try {
      final response = await _dio.post(
        '${_config.ragAdminApiUrl}/api/memory/sessions',
        data: {'id': id, 'name': name},
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        _logger.info('Session created successfully');
        return Session.fromJson(response.data);
      }
      _logger.warn('Failed to create session, status: ${response.statusCode}');
      return null;
    } catch (e) {
      _logger.error('Error creating session: $e');
      return null;
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    _logger.info('Deleting session: $sessionId');
    try {
      final response = await _dio.delete('${_config.ragAdminApiUrl}/api/memory/sessions/$sessionId');
      final success = response.statusCode == 204 || response.statusCode == 200;
      if (success) {
        _logger.info('Session deleted successfully');
      } else {
        _logger.warn('Failed to delete session, status: ${response.statusCode}');
      }
      return success;
    } catch (e) {
      _logger.error('Error deleting session: $e');
      return false;
    }
  }

  Future<List<ResponseMessage>> getMessages(String sessionId) async {
    _logger.debug('Fetching messages for session: $sessionId');
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/db/sessions/$sessionId/messages');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _logger.info('Successfully fetched ${data.length} messages for session: $sessionId');
        return data.map((e) {
          return ResponseMessage(
            content: e['content'],
            role: e['role'],
            timestamp: DateTime.parse(e['timestamp']),
          );
        }).toList();
      }
      _logger.warn('Failed to fetch messages, status: ${response.statusCode}');
      return [];
    } catch (e) {
      _logger.error('Error fetching messages: $e');
      return [];
    }
  }

  Stream<ResponseMessage> streamChat({
    required String prompt,
    required String sessionId,
    String? sessionName,
    required String planner,
    required String executor,
    required List<String> tags,
  }) {
    _logger.info('Starting streamChat for session: $sessionId');
    _logger.debug('Prompt: $prompt');
    
    // Construct the WebSocket URL via the rag-admin-api proxy
    final uri = Uri.parse(_config.ragAdminApiUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = (uri.port != 0 && ((uri.scheme == 'https' && uri.port != 443) || (uri.scheme == 'http' && uri.port != 80))) ? ':${uri.port}' : '';
    final wsUrl = '$wsScheme://${uri.host}$portPart/api/chat/v1/rag/chat/stream';

    _logger.info('Connecting to WebSocket: $wsUrl');
    
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final request = {
        'prompt': prompt,
        'session_id': sessionId,
        'session_name': sessionName,
        'planner': planner,
        'executor': executor,
        'tags': tags,
      };

      _logger.debug('Sending request: ${jsonEncode(request)}');
      channel.sink.add(jsonEncode(request));

      return channel.stream
          .timeout(Duration(seconds: _config.promptTimeoutSeconds))
          .map((event) {
            _logger.debug('Received chunk: $event');
            final data = jsonDecode(event);
            return ResponseMessage(
              content: data['chunk'] ?? '',
              sessionId: data['session_id'],
              messageId: data['id'],
              role: 'assistant',
              metadata: data['metadata'] ?? {},
              timestamp: DateTime.now(),
              isLast: data['is_last'] ?? false,
            );
          })
          .handleError((error) {
            _logger.error('Stream error: $error');
            throw error;
          });
    } catch (e) {
      _logger.error('Failed to connect or send to WebSocket: $e');
      rethrow;
    }
  }
}
