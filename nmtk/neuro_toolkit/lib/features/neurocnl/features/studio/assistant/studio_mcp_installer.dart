import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Desktop MCP config merge + install for external LLM harnesses.
class StudioMcpInstaller {
  StudioMcpInstaller({String? homeDirectory})
    : _homeDirectory = homeDirectory ?? _defaultHomeDirectory();

  final String? _homeDirectory;

  static const serverName = 'nmtk';

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static String? _defaultHomeDirectory() {
    if (kIsWeb) {
      return null;
    }
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
  }

  String? configPathForProvider(String providerId) {
    final home = _homeDirectory;
    if (home == null) {
      return null;
    }
    switch (providerId) {
      case 'claude':
        if (Platform.isMacOS) {
          return p.join(
            home,
            'Library',
            'Application Support',
            'Claude',
            'claude_desktop_config.json',
          );
        }
        if (Platform.isWindows) {
          final appData = Platform.environment['APPDATA'];
          if (appData == null) {
            return null;
          }
          return p.join(appData, 'Claude', 'claude_desktop_config.json');
        }
        return p.join(home, '.config', 'Claude', 'claude_desktop_config.json');
      case 'cursor-agent':
        return p.join(home, '.cursor', 'mcp.json');
      default:
        return null;
    }
  }

  String? skillPathForProvider(String providerId) {
    final home = _homeDirectory;
    if (home == null || providerId != 'antigravity') {
      return null;
    }
    return p.join(
      home,
      '.gemini',
      'antigravity-cli',
      'skills',
      'nmtk',
      'SKILL.md',
    );
  }

  bool isSkillInstalled(String providerId) {
    final path = skillPathForProvider(providerId);
    if (path == null) {
      return false;
    }
    return File(path).existsSync();
  }

  StudioMcpInstallResult installSkill({
    required String providerId,
    required String markdown,
  }) {
    final path = skillPathForProvider(providerId);
    if (path == null) {
      return const StudioMcpInstallResult(
        success: false,
        message: 'Skill install is not supported for this provider.',
        configPath: null,
      );
    }
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$markdown\n');
    return StudioMcpInstallResult(
      success: true,
      message: 'Installed NMTK skill at $path.',
      configPath: path,
    );
  }

  bool canAutoInstall(String providerId) =>
      configPathForProvider(providerId) != null;

  bool isInstalled(String providerId) {
    final path = configPathForProvider(providerId);
    if (path == null) {
      return false;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final servers = decoded['mcpServers'];
      if (servers is! Map<String, dynamic>) {
        return false;
      }
      return servers.containsKey(serverName);
    } on FormatException {
      return false;
    }
  }

  StudioMcpInstallResult install({
    required String providerId,
    required Map<String, dynamic> serverEntry,
  }) {
    final path = configPathForProvider(providerId);
    if (path == null) {
      return StudioMcpInstallResult(
        success: false,
        message:
            'Automatic MCP install is not supported for $providerId on this platform. Copy the JSON snippet instead.',
        configPath: null,
      );
    }

    final file = File(path);
    file.parent.createSync(recursive: true);

    Map<String, dynamic> root = {};
    if (file.existsSync()) {
      try {
        root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException {
        return StudioMcpInstallResult(
          success: false,
          message: 'Could not parse existing config at $path',
          configPath: path,
        );
      }
    }

    final merged = mergeMcpServerEntry(root, serverEntry);
    file.writeAsStringSync('${jsonEncode(merged)}\n');
    return StudioMcpInstallResult(
      success: true,
      message: 'Installed NMTK MCP at $path. Restart ${providerLabel(providerId)} to load it.',
      configPath: path,
    );
  }

  String providerLabel(String providerId) {
    switch (providerId) {
      case 'claude':
        return 'Claude Code / Claude Desktop';
      case 'cursor-agent':
        return 'Cursor';
      case 'codex':
        return 'Codex';
      case 'opencode':
        return 'OpenCode';
      case 'antigravity':
        return 'Antigravity CLI';
      default:
        return providerId;
    }
  }

  String snippetForProvider(Map<String, dynamic> serverEntry) {
    final block = buildHarnessServerBlock(serverEntry);
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {serverName: block},
    });
  }
}

class StudioMcpInstallResult {
  const StudioMcpInstallResult({
    required this.success,
    required this.message,
    required this.configPath,
  });

  final bool success;
  final String message;
  final String? configPath;
}

Map<String, dynamic> mergeMcpServerEntry(
  Map<String, dynamic> existing,
  Map<String, dynamic> serverEntry,
) {
  final merged = Map<String, dynamic>.from(existing);
  final servers = Map<String, dynamic>.from(
    merged['mcpServers'] as Map<String, dynamic>? ?? {},
  );
  servers[StudioMcpInstaller.serverName] = buildHarnessServerBlock(serverEntry);
  merged['mcpServers'] = servers;
  return merged;
}

Map<String, dynamic> buildHarnessServerBlock(Map<String, dynamic> serverEntry) {
  return {
    'command': serverEntry['command'],
    'args': serverEntry['args'],
    'env': serverEntry['env'],
  };
}
