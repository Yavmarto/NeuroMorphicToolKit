import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/widgets/loading_screen.dart';
// ignore: unnecessary_import — explicit Zeta import for clarity over re-export
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  group('NmtkLoadingScreen', () {
    testWidgets(
      '1. renders in waiting state without crashing and shows LinearProgressIndicator',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: NmtkLoadingScreen(
              state: NmtkReadinessState.waiting,
              progressMessage: 'Starting NeuroStudio…',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Starting NeuroStudio…'), findsOneWidget);
      },
    );

    testWidgets('2. renders in failed state and shows Retry button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NmtkLoadingScreen(
            state: NmtkReadinessState.failed,
            errorMessage: 'Backend timed out.',
            onRetry: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backend timed out.'), findsOneWidget);
      // No callback provided — button should not appear.
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('3. tapping Retry in failed state calls the onRetry callback', (
      tester,
    ) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: NmtkLoadingScreen(
            state: NmtkReadinessState.failed,
            errorMessage: 'A required service failed to start.',
            onRetry: () {
              retried = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('4. renders in degraded state and shows degraded message', (
      tester,
    ) async {
      const degradedMsg = 'Some optional services are unavailable.';

      await tester.pumpWidget(
        const MaterialApp(
          home: NmtkLoadingScreen(
            state: NmtkReadinessState.degraded,
            degradedMessage: degradedMsg,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(degradedMsg), findsOneWidget);
      // loading_screen uses ZetaIcons.warning_outline (Zeta design system)
      expect(find.byIcon(ZetaIcons.warning_outline), findsOneWidget);
    });

    testWidgets('5. degraded state fits narrow viewports', (tester) async {
      tester.view.physicalSize = const Size(260, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: NmtkLoadingScreen(
            state: NmtkReadinessState.degraded,
            degradedMessage:
                'Optional acceleration services are unavailable right now.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Optional acceleration services are unavailable right now.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. failed state fits narrow viewports', (tester) async {
      tester.view.physicalSize = const Size(260, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: NmtkLoadingScreen(
            state: NmtkReadinessState.failed,
            errorMessage: 'Backend timed out before reporting readiness.',
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Backend timed out before reporting readiness.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
