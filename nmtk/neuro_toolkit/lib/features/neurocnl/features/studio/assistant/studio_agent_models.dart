/// Models for the Studio assistant SSE chat stream.
library;

class StudioToolCallRequest {
  const StudioToolCallRequest({required this.name, this.arguments = const {}});

  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {
    'name': name,
    'arguments': arguments,
  };
}

class StudioLlmProviderInfo {
  const StudioLlmProviderInfo({
    required this.providerId,
    required this.label,
    required this.available,
    this.detail = '',
    this.supportsMcpInstall = false,
    this.mcpConfigHint,
    this.mcpInstalled = false,
  });

  final String providerId;
  final String label;
  final bool available;
  final String detail;
  final bool supportsMcpInstall;
  final String? mcpConfigHint;
  final bool mcpInstalled;

  StudioLlmProviderInfo copyWith({bool? mcpInstalled}) {
    return StudioLlmProviderInfo(
      providerId: providerId,
      label: label,
      available: available,
      detail: detail,
      supportsMcpInstall: supportsMcpInstall,
      mcpConfigHint: mcpConfigHint,
      mcpInstalled: mcpInstalled ?? this.mcpInstalled,
    );
  }

  factory StudioLlmProviderInfo.fromJson(Map<String, dynamic> json) {
    return StudioLlmProviderInfo(
      providerId: json['provider_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      detail: json['detail'] as String? ?? '',
      supportsMcpInstall: json['supports_mcp_install'] as bool? ?? false,
      mcpConfigHint: json['mcp_config_hint'] as String?,
    );
  }
}

class StudioAgentProvidersSnapshot {
  const StudioAgentProvidersSnapshot({
    this.activeProviderId,
    this.activeModel,
    this.mcpToolsReady = false,
    this.mcpToolCount = 0,
    this.probeHostNote,
    this.providers = const [],
  });

  final String? activeProviderId;
  final String? activeModel;
  final bool mcpToolsReady;
  final int mcpToolCount;
  final String? probeHostNote;
  final List<StudioLlmProviderInfo> providers;

  StudioAgentProvidersSnapshot copyWithProviders(
    List<StudioLlmProviderInfo> providers,
  ) {
    return StudioAgentProvidersSnapshot(
      activeProviderId: activeProviderId,
      activeModel: activeModel,
      mcpToolsReady: mcpToolsReady,
      mcpToolCount: mcpToolCount,
      probeHostNote: probeHostNote,
      providers: providers,
    );
  }

  factory StudioAgentProvidersSnapshot.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['providers'] as List<dynamic>? ?? const [];
    return StudioAgentProvidersSnapshot(
      activeProviderId: json['active_provider'] as String?,
      activeModel: json['active_model'] as String?,
      mcpToolsReady: json['mcp_tools_ready'] as bool? ?? false,
      mcpToolCount: json['mcp_tool_count'] as int? ?? 0,
      probeHostNote: json['probe_host_note'] as String?,
      providers: rawProviders
          .whereType<Map<String, dynamic>>()
          .map(StudioLlmProviderInfo.fromJson)
          .toList(growable: false),
    );
  }
}

class StudioAgentArtifact {
  const StudioAgentArtifact({
    required this.kind,
    this.title,
    this.path,
    this.uri,
    this.metadata = const {},
  });

  final String kind;
  final String? title;
  final String? path;
  final String? uri;
  final Map<String, dynamic> metadata;

  factory StudioAgentArtifact.fromJson(Map<String, dynamic> json) {
    return StudioAgentArtifact(
      kind: json['kind'] as String? ?? 'unknown',
      title: json['title'] as String?,
      path: json['path'] as String?,
      uri: json['uri'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  String? get cnlPatchText {
    final fromMeta = metadata['cnl'] ?? metadata['spec'] ?? metadata['patch'];
    if (fromMeta is String && fromMeta.trim().isNotEmpty) {
      return fromMeta;
    }
    if (kind.toLowerCase().contains('cnl') && title != null) {
      return title;
    }
    return null;
  }
}

class StudioAgentNextAction {
  const StudioAgentNextAction({
    required this.action,
    this.label,
    this.payload = const {},
    this.pipelineStep,
  });

  final String action;
  final String? label;
  final Map<String, dynamic> payload;
  final String? pipelineStep;

  factory StudioAgentNextAction.fromJson(
    Map<String, dynamic> json, {
    String? pipelineStep,
  }) {
    return StudioAgentNextAction(
      action: json['action'] as String? ?? '',
      label: json['label'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      pipelineStep: pipelineStep,
    );
  }
}

class StudioAgentToolResult {
  const StudioAgentToolResult({
    required this.status,
    required this.summary,
    this.details = const {},
    this.artifacts = const [],
    this.nextActions = const [],
  });

  final String status;
  final String summary;
  final Map<String, dynamic> details;
  final List<StudioAgentArtifact> artifacts;
  final List<StudioAgentNextAction> nextActions;

  factory StudioAgentToolResult.fromJson(Map<String, dynamic> json) {
    final artifacts = (json['artifacts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudioAgentArtifact.fromJson)
        .toList(growable: false);
    final nextActions = (json['next_actions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudioAgentNextAction.fromJson)
        .toList(growable: false);
    return StudioAgentToolResult(
      status: json['status'] as String? ?? 'error',
      summary: json['summary'] as String? ?? '',
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      artifacts: artifacts,
      nextActions: nextActions,
    );
  }
}

enum StudioAgentTimelineKind {
  userMessage,
  assistantText,
  toolCall,
  stepSuggestion,
}

enum StudioAgentToolStatus { running, succeeded, failed }

class StudioAgentTimelineEntry {
  const StudioAgentTimelineEntry({
    required this.id,
    required this.kind,
    this.text,
    this.toolName,
    this.toolStatus,
    this.toolArguments,
    this.toolResult,
    this.pipelineStep,
    this.suggestionLabel,
    this.suggestionReason,
  });

  final String id;
  final StudioAgentTimelineKind kind;
  final String? text;
  final String? toolName;
  final StudioAgentToolStatus? toolStatus;
  final Map<String, dynamic>? toolArguments;
  final StudioAgentToolResult? toolResult;
  final String? pipelineStep;
  final String? suggestionLabel;
  final String? suggestionReason;

  StudioAgentTimelineEntry copyWith({
    StudioAgentToolStatus? toolStatus,
    StudioAgentToolResult? toolResult,
  }) {
    return StudioAgentTimelineEntry(
      id: id,
      kind: kind,
      text: text,
      toolName: toolName,
      toolStatus: toolStatus ?? this.toolStatus,
      toolArguments: toolArguments,
      toolResult: toolResult ?? this.toolResult,
      pipelineStep: pipelineStep,
      suggestionLabel: suggestionLabel,
      suggestionReason: suggestionReason,
    );
  }
}

sealed class StudioAgentStreamEvent {
  const StudioAgentStreamEvent();
}

class StudioAgentAssistantDelta extends StudioAgentStreamEvent {
  const StudioAgentAssistantDelta(this.text);
  final String text;
}

class StudioAgentToolStarted extends StudioAgentStreamEvent {
  const StudioAgentToolStarted({required this.tool, this.arguments = const {}});

  final String tool;
  final Map<String, dynamic> arguments;
}

class StudioAgentToolFinished extends StudioAgentStreamEvent {
  const StudioAgentToolFinished({required this.tool, required this.result});

  final String tool;
  final StudioAgentToolResult result;
}

class StudioAgentStepSuggested extends StudioAgentStreamEvent {
  const StudioAgentStepSuggested({
    required this.step,
    this.reason,
    this.label,
    this.tool,
    this.action,
  });

  final String step;
  final String? reason;
  final String? label;
  final String? tool;
  final String? action;
}

class StudioAgentStreamDone extends StudioAgentStreamEvent {
  const StudioAgentStreamDone({required this.sessionId});
  final String sessionId;
}
