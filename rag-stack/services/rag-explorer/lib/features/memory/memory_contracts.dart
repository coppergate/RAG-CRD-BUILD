import 'dart:convert';

class MemoryScope {
  final int? sessionId;
  final String? userId;
  final int? projectId;
  final List<int> tags;

  const MemoryScope({
    this.sessionId,
    this.userId,
    this.projectId,
    this.tags = const [],
  });

  MemoryScope copyWith({
    Object? sessionId = _memoryScopeUnset,
    Object? userId = _memoryScopeUnset,
    Object? projectId = _memoryScopeUnset,
    Object? tags = _memoryScopeUnset,
  }) {
    return MemoryScope(
      sessionId: sessionId == _memoryScopeUnset
          ? this.sessionId
          : sessionId as int?,
      userId: userId == _memoryScopeUnset ? this.userId : userId as String?,
      projectId: projectId == _memoryScopeUnset
          ? this.projectId
          : projectId as int?,
      tags: tags == _memoryScopeUnset
          ? this.tags
          : List<int>.from(tags as List),
    );
  }

  factory MemoryScope.fromJson(Map<String, dynamic> json) {
    return MemoryScope(
      sessionId: _asInt(json['session_id'] ?? json['sessionId']),
      userId: _asString(json['user_id'] ?? json['userId']),
      projectId: _asInt(json['project_id'] ?? json['projectId']),
      tags: _parseIntList(json['tags']),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (sessionId != null) json['session_id'] = sessionId;
    if (userId != null && userId!.isNotEmpty) json['user_id'] = userId;
    if (projectId != null) json['project_id'] = projectId;
    if (tags.isNotEmpty) json['tags'] = tags;
    return json;
  }
}

class MemorySourceRef {
  final String sourceKind;
  final String sourceId;
  final String relationType;
  final double weight;
  final Map<String, dynamic> metadata;

  const MemorySourceRef({
    required this.sourceKind,
    required this.sourceId,
    required this.relationType,
    this.weight = 0.0,
    this.metadata = const {},
  });

  factory MemorySourceRef.fromJson(Map<String, dynamic> json) {
    return MemorySourceRef(
      sourceKind: _asString(json['source_kind'] ?? json['sourceKind']) ?? '',
      sourceId: _asString(json['source_id'] ?? json['sourceId']) ?? '',
      relationType:
          _asString(json['relation_type'] ?? json['relationType']) ?? '',
      weight: _asDouble(json['weight']) ?? 0.0,
      metadata: _asStringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'source_kind': sourceKind,
      'source_id': sourceId,
      'relation_type': relationType,
    };
    if (weight != 0.0) json['weight'] = weight;
    if (metadata.isNotEmpty) json['metadata'] = metadata;
    return json;
  }
}

class MemoryRecord {
  final int? memoryId;
  final String memoryType;
  final String? summary;
  final String? content;
  final double? salienceHint;
  final double? retentionHint;
  final bool pinned;
  final DateTime? expiresAt;
  final Map<String, dynamic> metadata;
  final List<MemorySourceRef> sourceRefs;
  final double? salience;
  final double? retentionScore;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? sessionId;
  final int? projectId;
  final String? userId;
  final double? rankScore;
  final String? whySelected;
  final int? tokenEstimate;

  const MemoryRecord({
    this.memoryId,
    this.memoryType = '',
    this.summary,
    this.content,
    this.salienceHint,
    this.retentionHint,
    this.pinned = false,
    this.expiresAt,
    this.metadata = const {},
    this.sourceRefs = const [],
    this.salience,
    this.retentionScore,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.sessionId,
    this.projectId,
    this.userId,
    this.rankScore,
    this.whySelected,
    this.tokenEstimate,
  });

  factory MemoryRecord.fromJson(Map<String, dynamic> json) {
    return MemoryRecord(
      memoryId: _asInt(json['memory_id'] ?? json['id']),
      memoryType: _asString(json['memory_type']) ?? '',
      summary: _asString(json['summary']),
      content: _asString(json['content']),
      salienceHint: _asDouble(json['salience_hint']),
      retentionHint: _asDouble(json['retention_hint']),
      pinned: _asBool(json['pinned']),
      expiresAt: _asDateTime(json['expires_at']),
      metadata: _asStringMap(json['metadata']),
      sourceRefs: _parseSourceRefs(json['source_refs']),
      salience: _asDouble(json['salience']),
      retentionScore: _asDouble(json['retention_score']),
      status: _asString(json['status']),
      createdAt: _asDateTime(json['created_at']),
      updatedAt: _asDateTime(json['updated_at']),
      sessionId: _asInt(json['session_id']),
      projectId: _asInt(json['project_id']),
      userId: _asString(json['user_id']),
      rankScore: _asDouble(json['rank_score']),
      whySelected: _asString(json['why_selected']),
      tokenEstimate: _asInt(json['token_estimate']),
    );
  }

  String get displayTitle {
    final normalizedSummary = summary?.trim();
    if (normalizedSummary != null && normalizedSummary.isNotEmpty) {
      return normalizedSummary;
    }

    final normalizedContent = content?.trim();
    if (normalizedContent != null && normalizedContent.isNotEmpty) {
      final firstLine = normalizedContent.split('\n').first.trim();
      if (firstLine.length <= 96) return firstLine;
      return '${firstLine.substring(0, 93)}...';
    }

    if (memoryType.isNotEmpty) {
      return memoryType;
    }

    if (memoryId != null) {
      return 'Memory ${memoryId!}';
    }

    return 'Untitled memory';
  }

  String? get contentPreview {
    final normalizedContent = content?.trim();
    if (normalizedContent == null || normalizedContent.isEmpty) return null;
    if (normalizedContent.length <= 220) return normalizedContent;
    return '${normalizedContent.substring(0, 217)}...';
  }

  MemoryRecord copyWith({
    int? memoryId,
    String? memoryType,
    String? summary,
    String? content,
    double? salienceHint,
    double? retentionHint,
    bool? pinned,
    DateTime? expiresAt,
    Map<String, dynamic>? metadata,
    List<MemorySourceRef>? sourceRefs,
    double? salience,
    double? retentionScore,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sessionId,
    int? projectId,
    String? userId,
    double? rankScore,
    String? whySelected,
    int? tokenEstimate,
  }) {
    return MemoryRecord(
      memoryId: memoryId ?? this.memoryId,
      memoryType: memoryType ?? this.memoryType,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      salienceHint: salienceHint ?? this.salienceHint,
      retentionHint: retentionHint ?? this.retentionHint,
      pinned: pinned ?? this.pinned,
      expiresAt: expiresAt ?? this.expiresAt,
      metadata: metadata ?? this.metadata,
      sourceRefs: sourceRefs ?? this.sourceRefs,
      salience: salience ?? this.salience,
      retentionScore: retentionScore ?? this.retentionScore,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionId: sessionId ?? this.sessionId,
      projectId: projectId ?? this.projectId,
      userId: userId ?? this.userId,
      rankScore: rankScore ?? this.rankScore,
      whySelected: whySelected ?? this.whySelected,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
    );
  }

  Map<String, dynamic> toWriteJson() {
    final json = <String, dynamic>{};
    if (memoryId != null) json['memory_id'] = memoryId;
    if (memoryType.isNotEmpty) json['memory_type'] = memoryType;
    if (summary != null && summary!.isNotEmpty) json['summary'] = summary;
    if (content != null && content!.isNotEmpty) json['content'] = content;
    if (salienceHint != null) json['salience_hint'] = salienceHint;
    if (retentionHint != null) json['retention_hint'] = retentionHint;
    if (pinned) json['pinned'] = true;
    if (expiresAt != null) {
      json['expires_at'] = expiresAt!.toUtc().toIso8601String();
    }
    if (metadata.isNotEmpty) json['metadata'] = metadata;
    if (sourceRefs.isNotEmpty) {
      json['source_refs'] = sourceRefs.map((ref) => ref.toJson()).toList();
    }
    return json;
  }
}

class MemoryPackBudget {
  final int? maxTokens;
  final int? usedTokens;
  final int? shortTermUsed;
  final int? longTermUsed;
  final int? persistentUsed;

  const MemoryPackBudget({
    this.maxTokens,
    this.usedTokens,
    this.shortTermUsed,
    this.longTermUsed,
    this.persistentUsed,
  });

  factory MemoryPackBudget.fromJson(Map<String, dynamic> json) {
    return MemoryPackBudget(
      maxTokens: _asInt(json['max_tokens']),
      usedTokens: _asInt(json['used_tokens']),
      shortTermUsed: _asInt(json['short_term_used']),
      longTermUsed: _asInt(json['long_term_used']),
      persistentUsed: _asInt(json['persistent_used']),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (maxTokens != null) json['max_tokens'] = maxTokens;
    if (usedTokens != null) json['used_tokens'] = usedTokens;
    if (shortTermUsed != null) json['short_term_used'] = shortTermUsed;
    if (longTermUsed != null) json['long_term_used'] = longTermUsed;
    if (persistentUsed != null) json['persistent_used'] = persistentUsed;
    return json;
  }
}

class MemoryDrop {
  final String memoryId;
  final String reason;

  const MemoryDrop({required this.memoryId, required this.reason});

  factory MemoryDrop.fromJson(Map<String, dynamic> json) {
    return MemoryDrop(
      memoryId: _asString(json['memory_id']) ?? '',
      reason: _asString(json['reason']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'memory_id': memoryId, 'reason': reason};
}

class MemoryConflict {
  final String winnerMemoryId;
  final String loserMemoryId;
  final String resolution;

  const MemoryConflict({
    required this.winnerMemoryId,
    required this.loserMemoryId,
    required this.resolution,
  });

  factory MemoryConflict.fromJson(Map<String, dynamic> json) {
    return MemoryConflict(
      winnerMemoryId: _asString(json['winner_memory_id']) ?? '',
      loserMemoryId: _asString(json['loser_memory_id']) ?? '',
      resolution: _asString(json['resolution']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'winner_memory_id': winnerMemoryId,
    'loser_memory_id': loserMemoryId,
    'resolution': resolution,
  };
}

class MemoryWriteRequest {
  final String requestId;
  final String correlationId;
  final MemoryScope scope;
  final List<MemoryRecord> writes;

  const MemoryWriteRequest({
    required this.requestId,
    required this.correlationId,
    required this.scope,
    required this.writes,
  });

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'correlation_id': correlationId,
    'scope': scope.toJson(),
    'writes': writes.map((item) => item.toWriteJson()).toList(),
  };
}

class MemoryRetrieveRequest {
  final String requestId;
  final String correlationId;
  final MemoryScope scope;
  final String query;
  final int limit;
  final double? minSalience;

  const MemoryRetrieveRequest({
    required this.requestId,
    required this.correlationId,
    required this.scope,
    required this.query,
    this.limit = 10,
    this.minSalience,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'request_id': requestId,
      'correlation_id': correlationId,
      'scope': scope.toJson(),
      'query': query,
      'limit': limit,
    };
    if (minSalience != null) json['min_salience'] = minSalience;
    return json;
  }
}

class MemoryPack {
  final String? requestId;
  final String? correlationId;
  final DateTime? generatedAt;
  final String? mode;
  final List<MemoryRecord> items;
  final MemoryPackBudget? tokenBudget;
  final List<MemoryDrop> dropped;
  final List<MemoryConflict> conflicts;
  final Map<String, dynamic> metadata;

  const MemoryPack({
    this.requestId,
    this.correlationId,
    this.generatedAt,
    this.mode,
    this.items = const [],
    this.tokenBudget,
    this.dropped = const [],
    this.conflicts = const [],
    this.metadata = const {},
  });

  factory MemoryPack.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? json['memories'] ?? const [];
    final rawMetadata = Map<String, dynamic>.from(json)
      ..remove('request_id')
      ..remove('correlation_id')
      ..remove('generated_at')
      ..remove('mode')
      ..remove('items')
      ..remove('memories')
      ..remove('token_budget')
      ..remove('dropped')
      ..remove('conflicts');

    return MemoryPack(
      requestId: _asString(json['request_id']),
      correlationId: _asString(json['correlation_id']),
      generatedAt: _asDateTime(json['generated_at']),
      mode: _asString(json['mode']),
      items: _parseRecordList(rawItems),
      tokenBudget: json['token_budget'] is Map
          ? MemoryPackBudget.fromJson(
              (json['token_budget'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      dropped: _parseDropList(json['dropped']),
      conflicts: _parseConflictList(json['conflicts']),
      metadata: rawMetadata,
    );
  }

  Map<String, dynamic> toJson() => {
    if (requestId != null) 'request_id': requestId,
    if (correlationId != null) 'correlation_id': correlationId,
    if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
    if (mode != null) 'mode': mode,
    'items': items.map((item) => item.toWriteJson()).toList(),
    if (tokenBudget != null) 'token_budget': tokenBudget!.toJson(),
    if (dropped.isNotEmpty)
      'dropped': dropped.map((drop) => drop.toJson()).toList(),
    if (conflicts.isNotEmpty)
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
    if (metadata.isNotEmpty) ...metadata,
  };
}

String _makeRequestId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

String _makeCorrelationId(String prefix) => _makeRequestId(prefix);

const Object _memoryScopeUnset = Object();

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

DateTime? _asDateTime(dynamic value) {
  final text = _asString(value);
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

Map<String, dynamic> _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<int> _parseIntList(dynamic value) {
  if (value is! List) return const [];
  final result = <int>[];
  for (final item in value) {
    final parsed = _asInt(item);
    if (parsed != null) result.add(parsed);
  }
  return result;
}

List<MemorySourceRef> _parseSourceRefs(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => MemorySourceRef.fromJson(
          entry.map((key, val) => MapEntry(key.toString(), val)),
        ),
      )
      .toList();
}

List<MemoryRecord> _parseRecordList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => MemoryRecord.fromJson(
          entry.map((key, val) => MapEntry(key.toString(), val)),
        ),
      )
      .toList();
}

List<MemoryDrop> _parseDropList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => MemoryDrop.fromJson(
          entry.map((key, val) => MapEntry(key.toString(), val)),
        ),
      )
      .toList();
}

List<MemoryConflict> _parseConflictList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => MemoryConflict.fromJson(
          entry.map((key, val) => MapEntry(key.toString(), val)),
        ),
      )
      .toList();
}

String prettyJson(Map<String, dynamic> json) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}
