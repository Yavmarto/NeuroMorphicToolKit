import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/setup_input_source_section.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

void main() {
  testWidgets('input source section toggles live NeuroSense mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: const SetupInputSourceSection()),
        ),
      ),
    );

    expect(find.byKey(const Key('setup-input-source-dataset')), findsOneWidget);
    expect(
      find.byKey(const Key('setup-input-source-live-sensor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('setup-input-source-live-sensor')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SetupInputSourceSection)),
    );
    expect(
      container.read(workspaceProvider).workspaceSourceKind,
      SetupInputSourceSection.liveSensorKind,
    );
  });
}
