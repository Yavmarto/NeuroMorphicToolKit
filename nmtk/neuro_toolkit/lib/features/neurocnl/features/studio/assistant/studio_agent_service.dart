import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';

/// HTTP client for `/api/studio/agent` session + SSE chat routes.
class StudioAgentService {
  StudioAgentService({required this.baseUrl, required this.httpClient});

  final String baseUrl;
  final http.Client httpClient;

  Future<String> createSession({String? workspaceId}) async {
    final uri = Uri.parse('$baseUrl/sessions');
    final body = <String, dynamic>{};
    if (workspaceId != null && workspaceId.trim().isNotEmpty) {
      body['workspace_id'] = workspaceId;
    }
    final response = await httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not start assistant session (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = decoded['session_id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw const StudioAgentException('Assistant session id was missing.');
    }
    return sessionId;
  }

  Future<StudioAgentProvidersSnapshot> fetchProviders() async {
    final uri = Uri.parse('$baseUrl/providers');
    final response = await httpClient.get(uri);
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not load assistant providers (${response.statusCode}).',
      );
    }
    return StudioAgentProvidersSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<StudioAgentProvidersSnapshot> updateActiveProvider({
    String? providerId,
    String? model,
  }) async {
    final uri = Uri.parse('$baseUrl/providers/active');
    final response = await httpClient.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (providerId != null) 'provider_id': providerId,
        if (model != null) 'model': model,
      }),
    );
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not update assistant provider (${response.statusCode}).',
      );
    }
    return StudioAgentProvidersSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> fetchMcpServerEntry({String? repoRoot}) async {
    final uri = Uri.parse('$baseUrl/mcp/server-entry').replace(
      queryParameters: repoRoot == null || repoRoot.isEmpty
          ? null
          : {'repo_root': repoRoot},
    );
    final response = await httpClient.get(uri);
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not load MCP server entry (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> fetchInstructionsMarkdown() async {
    final uri = Uri.parse('$baseUrl/instructions');
    final response = await httpClient.get(uri);
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not load assistant instructions (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['markdown'] as String? ?? '';
  }

  Future<Map<String, dynamic>> fetchSession(String sessionId) async {
    final uri = Uri.parse('$baseUrl/sessions/$sessionId');
    final response = await httpClient.get(uri);
    if (response.statusCode != 200) {
      throw StudioAgentException(
        'Could not load assistant session (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Stream<StudioAgentStreamEvent> chat({
    required String sessionId,
    String? message,
    List<StudioToolCallRequest> toolCalls = const [],
    String? assistantContent,
  }) async* {
    final uri = Uri.parse('$baseUrl/chat');
    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode({
      'session_id': sessionId,
      if (message != null) 'message': message,
      if (assistantContent != null) 'assistant_content': assistantContent,
      'tool_calls': toolCalls.map((call) => call.toJson()).toList(),
    });

    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw StudioAgentException(
        'Assistant chat failed (${response.statusCode}): $body',
      );
    }

    var eventName = '';
    final buffer = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final content = buffer.toString();
      var start = 0;
      while (true) {
        final newline = content.indexOf('\n', start);
        if (newline < 0) {
          buffer
            ..clear()
            ..write(content.substring(start));
          break;
        }
        final line = content.substring(start, newline).trimRight();
        start = newline + 1;
        if (line.isEmpty) {
          continue;
        }
        if (line.startsWith('event: ')) {
          eventName = line.substring(7).trim();
          continue;
        }
        if (!line.startsWith('data: ')) {
          continue;
        }
        final payload = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        final event = _parseEvent(eventName, payload);
        if (event != null) {
          yield event;
        }
        eventName = '';
      }
    }
  }

  StudioAgentStreamEvent? _parseEvent(
    String eventName,
    Map<String, dynamic> payload,
  ) {
    switch (eventName) {
      case 'assistant_delta':
        return StudioAgentAssistantDelta(payload['text'] as String? ?? '');
      case 'tool_started':
        return StudioAgentToolStarted(
          tool: payload['tool'] as String? ?? 'tool',
          arguments: (payload['arguments'] as Map<String, dynamic>?) ?? const {},
        );
      case 'tool_finished':
        return StudioAgentToolFinished(
          tool: payload['tool'] as String? ?? 'tool',
          result: StudioAgentToolResult.fromJson(
            (payload['result'] as Map<String, dynamic>?) ?? const {},
          ),
        );
      case 'step_suggested':
        return StudioAgentStepSuggested(
          step: payload['step'] as String? ?? '',
          reason: payload['reason'] as String?,
          label: payload['label'] as String?,
          tool: payload['tool'] as String?,
          action: payload['action'] as String?,
        );
      case 'done':
        return StudioAgentStreamDone(
          sessionId: payload['session_id'] as String? ?? '',
        );
      default:
        return null;
    }
  }
}

class StudioAgentException implements Exception {
  const StudioAgentException(this.message);
  final String message;

  @override
  String toString() => message;
}
