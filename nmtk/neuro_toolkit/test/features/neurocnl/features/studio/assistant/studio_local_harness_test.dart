import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_local_harness.dart';

void main() {
  test('mergeDesktopProbes adds desktop probe note', () {
    final snapshot = StudioAgentProvidersSnapshot(
      providers: const [
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
}
