import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('dialog surface stacks more than two actions on compact width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(375, 667)),
          child: Builder(
            builder: (context) {
              final actions = NmtkDialogSurface.layoutActions(context, <Widget>[
                const Text('One'),
                const Text('Two'),
                const Text('Three'),
              ]);
              expect(actions.length, greaterThan(3));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

  testWidgets('dialog surface keeps near-full width on compact phones', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(375, 667)),
          child: Builder(
            builder: (context) {
              final constraints = NmtkDialogSurface.constraints(
                context,
                maxWidth: 560,
              );
              expect(constraints.maxWidth, greaterThan(320));
              expect(constraints.maxWidth, lessThan(375));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });
}
