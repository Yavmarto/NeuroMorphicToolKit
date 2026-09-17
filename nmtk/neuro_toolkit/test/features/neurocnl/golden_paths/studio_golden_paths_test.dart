import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';

import 'golden_path_catalog.dart';
import 'golden_path_harness.dart';

/// NeuroStudio UI golden-path experiments — mirrors `neuro ci golden-paths`
/// (CEL-126) through the real Run step UI (CEL-261).
void main() {
  for (final combo in kStudioGoldenPathCombos) {
    group('studio golden path ${combo.id}', () {
      late StudioGoldenPathHarness harness;

      setUp(() async {
        harness = StudioGoldenPathHarness(combo);
        await harness.setUp();
      });

      tearDown(() async {
        await harness.tearDown();
      });

      testWidgets('Run step play drives generate for ${combo.platformId}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await harness.pumpStudio(tester);
        await harness.tapPlay(tester);

        if (combo.expectTrainable) {
          expect(find.byKey(const Key('stop-icon')), findsOneWidget);
          await harness.completeTrainableRun(tester);
          expect(
            harness.container.read(studioResultSessionProvider).phase,
            StudioResultSessionPhase.completed,
          );
          expect(
            harness.platformOutcome(),
            StudioPlatformOutcome.complete,
          );
          verify(
            harness.mockApi.runNotebook(
              notebookPath: anyNamed('notebookPath'),
              platform: combo.platformId,
              kernelName: anyNamed('kernelName'),
            ),
          ).called(1);
        } else {
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            harness.platformOutcome(),
            StudioPlatformOutcome.notApplicable,
          );
          verifyNever(
            harness.mockApi.runNotebook(
              notebookPath: anyNamed('notebookPath'),
              platform: anyNamed('platform'),
              kernelName: anyNamed('kernelName'),
            ),
          );
        }

        harness.verifyGenerateCalledWithFramework();
        // Run step always renders the view switch; non-canvas panels only
        // mount after leaving Architecture, which would hang pumpAndSettle here.
        expect(find.byKey(const Key('run-result-view-switch')), findsOneWidget);
      });
    });
  }
}
