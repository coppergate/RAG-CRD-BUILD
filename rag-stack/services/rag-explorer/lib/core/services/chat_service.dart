import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../app_config_provider.dart';
import '../models/response_message.dart';
import '../models/session.dart';
import '../models/tag.dart';
import '../utils/http_utils.dart';
import 'base_service.dart';
import 'log_service.dart';

final chatServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logNotifier = ref.watch(logProvider.notifier);
  return ChatService(dio, config, logNotifier);
});

class ChatService extends BaseService {
  ChatService(super.dio, super.config, super.logger);

  String _normalizeChatText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  Future<List<Session>> getSessions() {
    logger.debug('Fetching sessions from ${config.memoryUrl}/sessions');
    return getList(
      '${config.memoryUrl}/sessions',
      (e) => Session.fromJson(asStringMap(e)),
      logLabel: 'sessions',
    );
  }

  Future<Session?> createSession(String name) {
    logger.info('Creating session: $name');
    return postOne(
      '${config.memoryUrl}/sessions',
      {'name': name},
      (data) => Session.fromJson(asStringMap(data)),
      logLabel: 'create session',
    );
  }

  Future<bool> deleteSession(int sessionId) {
    logger.info('Deleting session: $sessionId');
    return deleteOne(
      '${config.memoryUrl}/sessions/$sessionId',
      logLabel: 'session $sessionId',
    );
  }

  Future<List<ResponseMessage>> getMessages(int sessionId) async {
    logger.debug('Fetching messages for session: $sessionId');
    try {
      final response = await dio.get(
        '${config.dbUrl}/sessions/$sessionId/messages',
      );
      if (!response.isSuccess) {
        logger.warn('Failed to fetch messages, status: ${response.statusCode}');
        return [];
      }
      final List<dynamic> data = response.data;
      logger.info(
        'Successfully fetched ${data.length} messages for session: $sessionId',
      );
      return data.map((e) {
        final metadata = _normalizeMetadata(e['metadata']);
        final planningResponse = e['planning_response'] == null
            ? null
            : _normalizeChatText(e['planning_response'].toString());
        final content = _normalizeChatText(e['content']?.toString() ?? '');
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
    } catch (e) {
      logger.error('Error fetching messages: $e');
      return [];
    }
  }

  Map<String, dynamic> _normalizeMetadata(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return _normalizeMessageSegments(Map<String, dynamic>.from(raw));
    }
    if (raw is Map) {
      return _normalizeMessageSegments(Map<String, dynamic>.from(raw));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _normalizeMessageSegments(Map<String, dynamic> metadata) {
    final raw = metadata['message_segments'];
    if (raw is! List || raw.isEmpty) {
      return metadata;
    }

    final normalizedSegments = raw
        .whereType<Map>()
        .map((segment) {
          final normalized = Map<String, dynamic>.from(segment);
          final content = normalized['content'];
          if (content is String) {
            normalized['content'] = _normalizeChatText(content);
          }
          return normalized;
        })
        .toList();

    return <String, dynamic>{
      ...metadata,
      'message_segments': normalizedSegments,
    };
  }

  bool _hasMessageSegments(Map<String, dynamic> metadata) {
    final raw = metadata['message_segments'];
    if (raw is! List) {
      return false;
    }
    return raw.isNotEmpty;
  }

  Future<List<Tag>> getTags() {
    logger.debug('Fetching tags from ${config.dbUrl}/tags');
    return getList(
      '${config.dbUrl}/tags',
      (e) => Tag.fromJson(asStringMap(e)),
      logLabel: 'tags',
    );
  }

  Stream<ResponseMessage> streamChat({
    required String prompt,
    required int sessionId,
    String? sessionName,
    required String planner,
    required String executor,
    required String embeddingModel,
    required List<int> tags,
  }) {
    logger.info('Starting streamChat for session: $sessionId');
    logger.debug('Prompt: $prompt');
    logger.debug('Stream tags: ${tags.isEmpty ? "<none>" : tags.join(", ")}');

    // Construct the WebSocket URL via the rag-admin-api proxy
    final uri = Uri.parse(config.ragAdminApiUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart =
        (uri.port != 0 &&
            ((uri.scheme == 'https' && uri.port != 443) ||
                (uri.scheme == 'http' && uri.port != 80)))
        ? ':${uri.port}'
        : '';
    final wsUrl =
        '$wsScheme://${uri.host}$portPart/api/chat/v1/rag/chat/stream';

    logger.info('Connecting to WebSocket: $wsUrl');

    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final request = {
        'prompt': prompt,
        'session_id': sessionId,
        'session_name': sessionName,
        'planner': planner,
        'executor': executor,
        'embedding_model': embeddingModel,
        'tags': tags,
      };

      logger.debug('Sending request: ${jsonEncode(request)}');
      channel.sink.add(jsonEncode(request));

      return channel.stream
          .timeout(
            Duration(seconds: config.promptTimeoutSeconds),
            onTimeout: (sink) {
              logger.warn(
                'Stream timed out after ${config.promptTimeoutSeconds} seconds of inactivity',
              );
              sink.addError(
                TimeoutException(
                  'No stream event received for ${config.promptTimeoutSeconds}s. The backend may be processing or the connection is idle.',
                  Duration(seconds: config.promptTimeoutSeconds),
                ),
              );
              sink.close();
            },
          )
          .map((event) {
            logger.debug('Received chunk: $event');
            final data = jsonDecode(event);
            return ResponseMessage(
              content: _normalizeChatText(
                data['result']?.toString() ?? data['error']?.toString() ?? '',
              ),
              sessionId: data['session_id'],
              messageId: data['id'],
              role: 'assistant',
              metadata: data['metadata'],
              timestamp: DateTime.now(),
              isLast: data['is_last'] ?? false,
              inConversation: data['in_conversation'] ?? false,
              planningResponse: data['planning_response'] == null
                  ? null
                  : _normalizeChatText(data['planning_response'].toString()),
            );
          })
          .handleError((error) {
            logger.error('Stream error: $error');
            throw error;
          });
    } catch (e) {
      logger.error('Failed to connect or send to WebSocket: $e');
      rethrow;
    }
  }

  Future<bool> updateSessionTags(int sessionId, List<int> tagIds) {
    logger.info('Updating tags for session $sessionId: $tagIds');
    return postVoid(
      '${config.dbUrl}/sessions/tags?session_id=$sessionId',
      {'tag_ids': tagIds},
      logLabel: 'session $sessionId tags',
    );
  }
}
