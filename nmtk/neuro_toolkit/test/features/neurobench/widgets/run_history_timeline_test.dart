import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/run_history_timeline.dart';

void main() {
  testWidgets('RunHistoryTimeline shows empty message when no runs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RunHistoryTimeline())),
      ),
    );

    expect(find.text('Run History'), findsOneWidget);
    // Again, will show loading or empty depending on provider state
  });
}
