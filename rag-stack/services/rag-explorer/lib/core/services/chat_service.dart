import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/app_config.dart';
import '../../app_config_provider.dart';
import '../models/response_message.dart';
import '../models/session.dart';
import '../models/tag.dart';
import 'log_service.dart';

final chatServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logNotifier = ref.watch(logProvider.notifier);
  return ChatService(dio, config, logNotifier);
});

class ChatService {
  final Dio _dio;
  final AppConfig _config;
  final LogNotifier _logger;
  ChatService(this._dio, this._config, this._logger);

  Future<List<Session>> getSessions() async {
    _logger.debug('Fetching sessions from ${_config.memoryUrl}/sessions');
    try {
      final response = await _dio.get('${_config.memoryUrl}/sessions');
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

  Future<Session?> createSession(String name) async {
    _logger.info('Creating session: $name');
    try {
      final response = await _dio.post(
        '${_config.memoryUrl}/sessions',
        data: {'name': name},
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

  Future<bool> deleteSession(int sessionId) async {
    _logger.info('Deleting session: $sessionId');
    try {
      final response = await _dio.delete(
        '${_config.memoryUrl}/sessions/$sessionId',
      );
      final success = response.statusCode == 204 || response.statusCode == 200;
      if (success) {
        _logger.info('Session deleted successfully');
      } else {
        _logger.warn(
          'Failed to delete session, status: ${response.statusCode}',
        );
      }
      return success;
    } catch (e) {
      _logger.error('Error deleting session: $e');
      return false;
    }
  }

  Future<List<ResponseMessage>> getMessages(int sessionId) async {
    _logger.debug('Fetching messages for session: $sessionId');
    try {
      final response = await _dio.get(
        '${_config.dbUrl}/sessions/$sessionId/messages',
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _logger.info(
          'Successfully fetched ${data.length} messages for session: $sessionId',
        );
        return data.map((e) {
          final metadata = _normalizeMetadata(e['metadata']);
          final planningResponse = e['planning_response']?.toString();
          final content = e['content']?.toString() ?? '';
          if (!_hasMessageSegments(metadata) &&
              ((planningResponse != null && planningResponse.isNotEmpty) ||
                  content.isNotEmpty)) {
            metadata['message_segments'] = <Map<String, dynamic>>[
              if (planningResponse != null && planningResponse.isNotEmpty)
                {'kind': 'planning', 'content': planningResponse},
              if (content.isNotEmpty) {'kind': 'content', 'content': content},
            ];
          }

          return ResponseMessage(
            content: content,
            planningResponse: planningResponse,
            role: e['role'],
            timestamp: DateTime.parse(e['timestamp']),
            metadata: metadata.isEmpty ? null : metadata,
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

  Map<String, dynamic> _normalizeMetadata(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  bool _hasMessageSegments(Map<String, dynamic> metadata) {
    final raw = metadata['message_segments'];
    if (raw is! List) {
      return false;
    }
    return raw.isNotEmpty;
  }

  Future<List<Tag>> getTags() async {
    _logger.debug('Fetching tags from ${_config.dbUrl}/tags');
    try {
      final response = await _dio.get('${_config.dbUrl}/tags');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _logger.info('Successfully fetched ${data.length} tags');
        return data.map((e) => Tag.fromJson(e)).toList();
      }
      _logger.warn('Failed to fetch tags, status: ${response.statusCode}');
      return [];
    } catch (e) {
      _logger.error('Error fetching tags: $e');
      return [];
    }
  }

  Stream<ResponseMessage> streamChat({
    required String prompt,
    required int sessionId,
    String? sessionName,
    required String planner,
    required String executor,
    required List<int> tags,
  }) {
    _logger.info('Starting streamChat for session: $sessionId');
    _logger.debug('Prompt: $prompt');
    _logger.debug('Stream tags: ${tags.isEmpty ? "<none>" : tags.join(", ")}');

    // Construct the WebSocket URL via the rag-admin-api proxy
    final uri = Uri.parse(_config.ragAdminApiUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart =
        (uri.port != 0 &&
            ((uri.scheme == 'https' && uri.port != 443) ||
                (uri.scheme == 'http' && uri.port != 80)))
        ? ':${uri.port}'
        : '';
    final wsUrl =
        '$wsScheme://${uri.host}$portPart/api/chat/v1/rag/chat/stream';

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
          .timeout(
            Duration(seconds: _config.promptTimeoutSeconds),
            onTimeout: (sink) {
              _logger.warn(
                'Stream timed out after ${_config.promptTimeoutSeconds} seconds of inactivity',
              );
              sink.addError(
                TimeoutException(
                  'No stream event received for ${_config.promptTimeoutSeconds}s. The backend may be processing or the connection is idle.',
                  Duration(seconds: _config.promptTimeoutSeconds),
                ),
              );
              sink.close();
            },
          )
          .map((event) {
            _logger.debug('Received chunk: $event');
            final data = jsonDecode(event);
            return ResponseMessage(
              content: data['result'] ?? (data['error'] ?? ''),
              sessionId: data['session_id'],
              messageId: data['id'],
              role: 'assistant',
              metadata: data['metadata'],
              timestamp: DateTime.now(),
              isLast: data['is_last'] ?? false,
              inConversation: data['in_conversation'] ?? false,
              planningResponse: data['planning_response'],
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

  Future<bool> updateSessionTags(int sessionId, List<int> tagIds) async {
    _logger.info('Updating tags for session $sessionId: $tagIds');
    try {
      final response = await _dio.post(
        '${_config.dbUrl}/sessions/tags?session_id=$sessionId',
        data: {'tag_ids': tagIds},
      );
      return response.statusCode == 204;
    } catch (e) {
      _logger.error('Error updating session tags: $e');
      return false;
    }
  }
}
