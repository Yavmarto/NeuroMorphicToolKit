import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';

/// Desktop-only CLI harness probe + run (mirrors suite_api subprocess_cli).
class StudioLocalHarness {
  StudioLocalHarness._();

  static const cliProviderIds = <String>{
    'claude',
    'codex',
    'cursor-agent',
    'opencode',
    'antigravity',
  };

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static bool isCliProvider(String? providerId) =>
      providerId != null && cliProviderIds.contains(providerId);

  /// Mark CLI providers available when binaries exist on this desktop.
  static StudioAgentProvidersSnapshot mergeDesktopProbes(
    StudioAgentProvidersSnapshot snapshot,
  ) {
    if (!isSupported) {
      return snapshot;
    }
    final providers = snapshot.providers
        .map((provider) {
          if (!cliProviderIds.contains(provider.providerId)) {
            return provider;
          }
          final binary = _binaryForProvider(provider.providerId);
          if (binary == null) {
            return provider;
          }
          return StudioLlmProviderInfo(
            providerId: provider.providerId,
            label: provider.label,
            available: true,
            detail: 'desktop:$binary',
            supportsMcpInstall: provider.supportsMcpInstall,
            mcpConfigHint: provider.mcpConfigHint,
            mcpInstalled: provider.mcpInstalled,
          );
        })
        .toList(growable: false);
    return snapshot.copyWithProviders(providers).copyWith(
      probeHostNote:
          'CLI harnesses run on this desktop. HTTP providers (Ollama, LM Studio) '
          'are detected on the connected backend.',
    );
  }

  static Future<StudioLocalHarnessResult?> maybeRun({
    required String providerId,
    required List<Map<String, dynamic>> messages,
    required String instructionsMarkdown,
    String? model,
  }) async {
    if (!isSupported || !isCliProvider(providerId)) {
      return null;
    }
    final spec = _specForProvider(providerId);
    if (spec == null) {
      return null;
    }
    final binary = await resolveExecutable(spec.binary);
    if (binary == null) {
      return null;
    }
    final prompt = _formatPrompt(
      messages: messages,
      instructionsMarkdown: instructionsMarkdown,
    );
    final argv = [
      binary,
      ...spec.prefixArgs,
      prompt,
      ...spec.suffixArgs,
    ];
    final process = await Process.start(
      argv.first,
      argv.sublist(1),
      runInShell: false,
    );
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StudioLocalHarnessException(
        '${spec.binary} exited $exitCode: ${stderr.trim()}',
      );
    }
    return _parseResponse(stdout);
  }

  static Future<String?> resolveExecutable(String binary) async {
    if (!isSupported) {
      return null;
    }
    if (Platform.isWindows) {
      final result = await Process.run('where', [binary], runInShell: false);
      if (result.exitCode != 0) {
        return null;
      }
      final line = (result.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      return line.isEmpty ? null : line;
    }
    final result = await Process.run('which', [binary], runInShell: false);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  static String? _binaryForProvider(String providerId) {
    final spec = _specForProvider(providerId);
    if (spec == null) {
      return null;
    }
    final path = Platform.environment['PATH'];
    if (path == null) {
      return null;
    }
    final names = Platform.isWindows
        ? <String>[spec.binary, '${spec.binary}.exe', '${spec.binary}.cmd']
        : <String>[spec.binary];
    for (final dir in path.split(Platform.pathSeparator)) {
      for (final name in names) {
        final candidate = '$dir${Platform.pathSeparator}$name';
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    }
    return null;
  }

  static _HarnessSpec? _specForProvider(String providerId) {
    switch (providerId) {
      case 'claude':
        return const _HarnessSpec('claude', prefixArgs: ['--print']);
      case 'codex':
        return const _HarnessSpec('codex', prefixArgs: ['exec']);
      case 'cursor-agent':
        return const _HarnessSpec('cursor-agent');
      case 'opencode':
        return const _HarnessSpec('opencode');
      case 'antigravity':
        return const _HarnessSpec(
          'agy',
          prefixArgs: ['-p'],
          suffixArgs: ['--output-format', 'json'],
        );
      default:
        return null;
    }
  }

  static String _formatPrompt({
    required List<Map<String, dynamic>> messages,
    required String instructionsMarkdown,
  }) {
    final lines = <String>[];
    final hasInstructions = messages.any(
      (message) =>
          message['role'] == 'system' &&
          (message['content'] as String? ?? '').contains('nmtk-studio-assistant'),
    );
    if (!hasInstructions && instructionsMarkdown.trim().isNotEmpty) {
      lines.add(instructionsMarkdown.trim());
    }
    for (final message in messages) {
      final role = message['role'] as String? ?? 'user';
      final content = message['content'];
      if (role == 'tool') {
        lines.add('tool(${message['tool']}): ${jsonEncode(content)}');
        continue;
      }
      if (content is String && content.trim().isNotEmpty) {
        lines.add('$role: $content');
      }
    }
    lines.add(
      'Respond with JSON only: {"content":"assistant text","tool_calls":'
      '[{"name":"tool_name","arguments":{}}]}. '
      'Use an empty tool_calls array when no tool is needed.',
    );
    lines.add('assistant:');
    return lines.join('\n');
  }

  static StudioLocalHarnessResult _parseResponse(String text) {
    var candidate = text.trim();
    if (candidate.startsWith('```')) {
      candidate = candidate.replaceAll('`', '').trim();
      if (candidate.startsWith('json')) {
        candidate = candidate.substring(4).trim();
      }
    }
    try {
      final payload = jsonDecode(candidate) as Map<String, dynamic>;
      final content = (payload['content'] as String?) ??
          (payload['response'] as String?) ??
          text.trim();
      final rawCalls = payload['tool_calls'] as List<dynamic>? ??
          ((payload['message'] as Map<String, dynamic>?)?['tool_calls']
              as List<dynamic>?);
      final toolCalls = <StudioToolCallRequest>[];
      for (final call in rawCalls ?? const []) {
        if (call is! Map<String, dynamic>) {
          continue;
        }
        final name = call['name'] as String?;
        if (name == null || name.isEmpty) {
          continue;
        }
        final args = call['arguments'];
        toolCalls.add(
          StudioToolCallRequest(
            name: name,
            arguments: args is Map<String, dynamic> ? args : const {},
          ),
        );
      }
      return StudioLocalHarnessResult(
        content: content,
        toolCalls: toolCalls,
      );
    } on FormatException {
      return StudioLocalHarnessResult(content: text.trim());
    }
  }
}

class StudioLocalHarnessResult {
  const StudioLocalHarnessResult({
    required this.content,
    this.toolCalls = const [],
  });

  final String content;
  final List<StudioToolCallRequest> toolCalls;
}

class StudioLocalHarnessException implements Exception {
  StudioLocalHarnessException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _HarnessSpec {
  const _HarnessSpec(
    this.binary, {
    this.prefixArgs = const [],
    this.suffixArgs = const [],
  });

  final String binary;
  final List<String> prefixArgs;
  final List<String> suffixArgs;
}

extension on StudioAgentProvidersSnapshot {
  StudioAgentProvidersSnapshot copyWith({String? probeHostNote}) {
    return StudioAgentProvidersSnapshot(
      activeProviderId: activeProviderId,
      activeModel: activeModel,
      mcpToolsReady: mcpToolsReady,
      mcpToolCount: mcpToolCount,
      probeHostNote: probeHostNote ?? this.probeHostNote,
      providers: providers,
    );
  }
}
