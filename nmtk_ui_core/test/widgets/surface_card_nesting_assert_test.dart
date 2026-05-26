// Regression test for zeta-card-reduction Task 3: NmtkSurfaceCard must not be
// nested inside another NmtkSurfaceCard. The widget enforces this in debug
// builds via a `findAncestorWidgetOfExactType` assertion — this test locks
// that contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('NmtkSurfaceCard alone in the tree builds without error',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NmtkSurfaceCard(
            title: 'lonely',
            child: Text('child'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('lonely'), findsOneWidget);
  });

  testWidgets(
    'nested NmtkSurfaceCard throws a FlutterError in debug builds',
    (tester) async {
      // Catch all errors thrown during the failed mount so the layout
      // RenderFlex overflow that follows the assertion failure doesn't fail
      // the test.
      final errors = <Object>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSurfaceCard(
              title: 'outer',
              child: NmtkSurfaceCard(
                title: 'inner',
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      FlutterError.onError = originalOnError;

      expect(
        errors,
        isNotEmpty,
        reason: 'The nesting assert must produce at least one Flutter error.',
      );
      final assertionError = errors.firstWhere(
        (e) => e.toString().contains('must not be nested'),
        orElse: () => throw StateError(
          'No assertion mentioning "must not be nested" was thrown. '
          'Errors observed: $errors',
        ),
      );
      expect(assertionError, isA<FlutterError>());
    },
  );
}
