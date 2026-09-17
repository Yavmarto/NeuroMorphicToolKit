import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/parameter_explorer.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  testWidgets(
    'ParameterExplorer shows placeholder when no numeric values in spec',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            specTextProvider.overrideWith(
              () => _FakeSpecTextController('no parameters here'),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ParameterExplorer())),
        ),
      );

      expect(
        find.textContaining('Parameters will appear here'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ParameterExplorer shows sliders for numeric patterns in spec', (
    WidgetTester tester,
  ) async {
    const spec = '''
# Test spec
membrane potential exceeds 1.5
refractory period of 0.005 seconds
using 100 neurons
''';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          specTextProvider.overrideWith(() => _FakeSpecTextController(spec)),
        ],
        child: const MaterialApp(home: Scaffold(body: ParameterExplorer())),
      ),
    );

    // Should not show placeholder
    expect(find.textContaining('Parameters will appear here'), findsNothing);

    // Sliders for each found parameter
    expect(find.text('Threshold'), findsOneWidget);
    expect(find.text('Refractory Period'), findsOneWidget);
    expect(find.text('Population Size'), findsOneWidget);

    // Value chips
    expect(find.text('1.5 '), findsOneWidget);
    expect(find.text('0.005 s'), findsOneWidget);
    expect(find.text('100 neurons'), findsOneWidget);

    // Sliders
    expect(find.byType(Slider), findsNWidgets(3));
  });
}

class _FakeSpecTextController extends SpecTextController {
  _FakeSpecTextController(this._initial);
  final String _initial;
  @override
  String build() => _initial;
}
