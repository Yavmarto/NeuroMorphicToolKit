import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_mcp_installer.dart';

void main() {
  test('mergeMcpServerEntry adds nmtk server block', () {
    final merged = mergeMcpServerEntry(
      {'existing': true},
      {
        'command': 'python3',
        'args': ['-m', 'tools.nmtk_mcp_server'],
        'env': {'NMTK_SUITE_API_URL': 'http://127.0.0.1:9000'},
      },
    );

    expect(merged['existing'], isTrue);
    final servers = merged['mcpServers'] as Map<String, dynamic>;
    expect(servers['nmtk'], isNotNull);
    expect(servers['nmtk']['command'], 'python3');
  });

  test('install writes Claude config under home directory', () {
    final tempHome = Directory.systemTemp.createTempSync('studio-mcp-').path;
    final installer = StudioMcpInstaller(homeDirectory: tempHome);
    final result = installer.install(
      providerId: 'claude',
      serverEntry: {
        'command': 'python3',
        'args': ['-m', 'tools.nmtk_mcp_server'],
        'env': {
          'NMTK_SUITE_API_URL': 'http://127.0.0.1:9000',
          'NMTK_REPO_ROOT': '/tmp/nmtk',
        },
      },
    );

    expect(result.success, isTrue);
    expect(installer.isInstalled('claude'), isTrue);
  });

  test('installSkill writes antigravity skill file', () {
    final tempHome = Directory.systemTemp.createTempSync('studio-skill-').path;
    final installer = StudioMcpInstaller(homeDirectory: tempHome);
    final result = installer.installSkill(
      providerId: 'antigravity',
      markdown: '# NMTK skill',
    );

    expect(result.success, isTrue);
    expect(installer.isSkillInstalled('antigravity'), isTrue);
  });
}
