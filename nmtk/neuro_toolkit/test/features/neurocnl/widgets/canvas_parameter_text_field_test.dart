import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';

void main() {
  testWidgets('keeps full draft text across pumps before debounce fires', (
    WidgetTester tester,
  ) async {
    String? committed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasParameterTextField(
            label: 'threshold',
            value: '1.0',
            commitDebounce: const Duration(milliseconds: 200),
            onCommit: (String value) => committed = value,
          ),
        ),
      ),
    );

    final fieldFinder = find.byType(CanvasParameterTextField);
    await tester.tap(fieldFinder);
    await tester.pump();

    for (var i = 1; i <= '0.123'.length; i++) {
      await tester.enterText(fieldFinder, '0.123'.substring(0, i));
      await tester.pump(const Duration(milliseconds: 30));
    }

    final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '0.123');
    expect(committed, isNull);

    await tester.pump(const Duration(milliseconds: 250));
    expect(committed, '0.123');
  });

  testWidgets('commits a draft when torn down inside the debounce window', (
    WidgetTester tester,
  ) async {
    // Selecting another node, closing the Inspector or advancing the stepper
    // all remove this field from the tree. Cancelling the pending timer without
    // flushing silently discarded whatever the user had just typed.
    String? committed;

    Widget host({required bool showField}) => MaterialApp(
      home: Scaffold(
        body: showField
            ? CanvasParameterTextField(
                label: 'rows',
                value: '1000',
                commitDebounce: const Duration(milliseconds: 200),
                onCommit: (String value) => committed = value,
              )
            : const SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(host(showField: true));
    await tester.enterText(find.byType(CanvasParameterTextField), '256');
    await tester.pump(const Duration(milliseconds: 50));
    expect(committed, isNull, reason: 'debounce has not elapsed yet');

    // Tear the field down well before the 200ms debounce would have fired.
    await tester.pumpWidget(host(showField: false));

    expect(committed, '256');
  });

  testWidgets('does not re-commit a value already committed on blur', (
    WidgetTester tester,
  ) async {
    final List<String> commits = <String>[];

    Widget host({required bool showField}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (showField)
              CanvasParameterTextField(
                label: 'rows',
                value: '1000',
                commitDebounce: const Duration(milliseconds: 200),
                onCommit: commits.add,
              ),
            const TextField(key: Key('elsewhere')),
          ],
        ),
      ),
    );

    await tester.pumpWidget(host(showField: true));
    await tester.enterText(find.byType(CanvasParameterTextField), '256');
    await tester.pump(const Duration(milliseconds: 250));
    expect(commits, <String>['256']);

    await tester.pumpWidget(host(showField: false));

    expect(commits, <String>['256'], reason: 'teardown must not duplicate it');
  });
}
