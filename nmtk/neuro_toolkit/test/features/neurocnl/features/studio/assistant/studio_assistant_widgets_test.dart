import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/build_timeline.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_notifier.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/tool_call_card.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/ui_core/contrast_utils.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStudioAgentNotifier extends StudioAgentNotifier {
  _FakeStudioAgentNotifier(this.seed);

  final StudioAgentState seed;

  @override
  StudioAgentState build() => seed;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
  });

  Widget wrap(
    Widget child, {
    List<Override> overrides = const [],
    ThemeMode mode = ThemeMode.light,
  }) {
    return ProviderScope(
      overrides: overrides,
      child: NmtkZetaTheme.wrap(
        initialThemeMode: mode,
        builder: (context, light, dark, effective) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: effective,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('ToolCallCard shows tool name and summary', (tester) async {
    const entry = StudioAgentTimelineEntry(
      id: 'tool-1',
      kind: StudioAgentTimelineKind.toolCall,
      toolName: 'validate_cnl',
      toolStatus: StudioAgentToolStatus.succeeded,
      toolResult: StudioAgentToolResult(
        status: 'ok',
        summary: 'NeuroCNL validation completed.',
      ),
    );

    await tester.pumpWidget(wrap(ToolCallCard(entry: entry)));
    await tester.pumpAndSettle();

    expect(find.text('validate_cnl'), findsOneWidget);
    expect(find.text('NeuroCNL validation completed.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('BuildTimeline renders streamed tool step and guarded chip', (
    tester,
  ) async {
    final fakeState = StudioAgentState(
      timeline: [
        const StudioAgentTimelineEntry(
          id: 'tool-1',
          kind: StudioAgentTimelineKind.toolCall,
          toolName: 'validate_cnl',
          toolStatus: StudioAgentToolStatus.succeeded,
          toolResult: StudioAgentToolResult(
            status: 'ok',
            summary: 'Valid CNL.',
            nextActions: [
              StudioAgentNextAction(
                action: 'submit_simulation',
                label: 'Run sim',
              ),
            ],
          ),
        ),
        const StudioAgentTimelineEntry(
          id: 'step-1',
          kind: StudioAgentTimelineKind.stepSuggestion,
          pipelineStep: 'run',
          suggestionLabel: 'Open Run',
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        BuildTimeline(entries: fakeState.timeline),
        overrides: [
          studioAgentNotifierProvider.overrideWith(
            () => _FakeStudioAgentNotifier(fakeState),
          ),
          unlockedStepsProvider.overrideWith((ref) => {'selectData'}),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('validate_cnl'), findsOneWidget);
    expect(find.text('Run sim'), findsOneWidget);
    final lockedChip = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'Run sim'),
    );
    expect(lockedChip.onPressed, isNull);
  });

  test('applyStepSuggestion advances pipeline when step is unlocked', () {
    final container = ProviderContainer(
      overrides: [
        unlockedStepsProvider.overrideWith((ref) => {'selectData', 'run'}),
      ],
    );
    addTearDown(container.dispose);

    final applied = container
        .read(studioAgentNotifierProvider.notifier)
        .applyStepSuggestion('run');

    expect(applied, isTrue);
    expect(container.read(workspaceProvider).activePipelineStep, 'run');
  });

  testWidgets('StudioAssistantPanel shows provider setup controls', (
    tester,
  ) async {
    const snapshot = StudioAgentProvidersSnapshot(
      activeProviderId: 'claude',
      activeModel: 'sonnet',
      mcpToolsReady: true,
      mcpToolCount: 6,
      providers: [
        StudioLlmProviderInfo(
          providerId: 'ollama',
          label: 'Ollama',
          available: true,
        ),
        StudioLlmProviderInfo(
          providerId: 'claude',
          label: 'Claude Code',
          available: true,
          supportsMcpInstall: true,
          mcpConfigHint:
              '~/Library/Application Support/Claude/claude_desktop_config.json',
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(
        const StudioAssistantPanel(),
        overrides: [
          studioAgentNotifierProvider.overrideWith(
            () => _FakeStudioAgentNotifier(
              const StudioAgentState(providersSnapshot: snapshot),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LLM provider'), findsOneWidget);
    expect(find.text('Model name'), findsOneWidget);
    expect(find.textContaining('Build tools ready'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Install MCP'), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '$mode: StudioAssistantPanel chrome icons clear 3:1 on their surfaces',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            StudioAssistantPanel(onClose: () {}),
            mode: mode,
            overrides: [
              studioAgentNotifierProvider.overrideWith(
                () => _FakeStudioAgentNotifier(const StudioAgentState()),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final colors = Zeta.of(
          tester.element(find.byType(StudioAssistantPanel)),
        ).colors;
        final closeIcon = tester.widget<Icon>(find.byIcon(ZetaIcons.close));
        expect(
          nmtkContrastRatio(closeIcon.color!, colors.surfaceDefault),
          greaterThanOrEqualTo(3.0),
        );

        final sendFinder = find.descendant(
          of: find.byType(FilledButton).last,
          matching: find.byIcon(ZetaIcons.send),
        );
        final sendElement = tester.element(sendFinder);
        final sendIcon = tester.widget<Icon>(sendFinder);
        final sendColor =
            sendIcon.color ?? IconTheme.of(sendElement).color!;
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: sendFinder,
            matching: find.byType(FilledButton),
          ),
        );
        final buttonBg =
            button.style?.backgroundColor?.resolve({}) ??
            Theme.of(sendElement).colorScheme.primary;
        expect(
          nmtkContrastRatio(sendColor, buttonBg),
          greaterThanOrEqualTo(3.0),
        );
      },
    );
  }

  testWidgets('StudioAssistantPanel shows timeline placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const StudioAssistantPanel(),
        overrides: [
          studioAgentNotifierProvider.overrideWith(
            () => _FakeStudioAgentNotifier(const StudioAgentState()),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Studio assistant'), findsOneWidget);
    expect(
      find.text('Assistant steps will appear here as tools run.'),
      findsOneWidget,
    );
  });
}
