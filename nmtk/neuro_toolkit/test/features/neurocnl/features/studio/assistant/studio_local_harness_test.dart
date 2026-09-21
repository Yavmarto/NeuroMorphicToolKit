import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_local_harness.dart';

void main() {
  test('mergeDesktopProbes adds desktop probe note', () {
    const snapshot = StudioAgentProvidersSnapshot(
      providers: [
        StudioLlmProviderInfo(
          providerId: 'ollama',
          label: 'Ollama',
          available: true,
          detail: 'server',
        ),
      ],
    );
    final merged = StudioLocalHarness.mergeDesktopProbes(snapshot);
    expect(merged.probeHostNote, contains('desktop'));
    expect(merged.providers.single.available, isTrue);
  });

  test('isCliProvider recognizes harness ids', () {
    expect(StudioLocalHarness.isCliProvider('claude'), isTrue);
    expect(StudioLocalHarness.isCliProvider('ollama'), isFalse);
  });

  test('binaryForProviderInPath splits colon-separated PATH entries', () {
    if (!StudioLocalHarness.isSupported) {
      return;
    }
    final tempDir = Directory.systemTemp.createTempSync('studio_harness_path_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final fakeBinary = File('${tempDir.path}/claude');
    fakeBinary.writeAsStringSync('');

    final pathEnv =
        '/usr/bin:/opt/homebrew/bin:${tempDir.path}:/home/user/.local/bin';
    final resolved = StudioLocalHarness.binaryForProviderInPath(
      'claude',
      pathEnv,
    );

    expect(resolved, '${tempDir.path}/claude');
  });

  test('firstAvailableCliProviderId prefers first installed CLI', () {
    const providers = [
      StudioLlmProviderInfo(
        providerId: 'ollama',
        label: 'Ollama',
        available: true,
        detail: 'server',
      ),
      StudioLlmProviderInfo(
        providerId: 'claude',
        label: 'Claude',
        available: true,
        detail: 'desktop',
      ),
      StudioLlmProviderInfo(
        providerId: 'codex',
        label: 'Codex',
        available: true,
        detail: 'desktop',
      ),
    ];
    expect(StudioLocalHarness.firstAvailableCliProviderId(providers), 'claude');
  });
}
