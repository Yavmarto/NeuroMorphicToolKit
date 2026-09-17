import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/akida_deploy_panel.dart';

class MockAkidaDeployController extends AkidaDeployController {
  MockAkidaDeployController(this._initialState);
  final AkidaDeployState _initialState;

  @override
  AkidaDeployState build() => _initialState;

  @override
  Future<void> validate(String spec) async {}

  @override
  void selectBitWidth(int bitWidth) {}

  @override
  void selectVersion(String akidaVersion) {}

  @override
  void setHardwareUrl(String url) {}
}

class MockSpecTextController extends SpecTextController {
  MockSpecTextController(this._initialState);
  final String _initialState;

  @override
  String build() => _initialState;

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> set(String text) async {}

  @override
  Future<void> flush() async {}
}

Widget buildWidget(AkidaDeployState state, {String spec = 'spec'}) {
  return ProviderScope(
    overrides: [
      akidaDeployProvider.overrideWith(() => MockAkidaDeployController(state)),
      specTextProvider.overrideWith(() => MockSpecTextController(spec)),
    ],
    child: const MaterialApp(home: Scaffold(body: AkidaDeployPanel())),
  );
}

void main() {
  group('AkidaDeployPanel', () {
    testWidgets('renders mapped output and controls when ready', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(
          const AkidaDeployState(
            phase: AkidaDeployPhase.ready,
            supportState: 'exportable_scaffold_with_warnings',
            akidaVersion: 'akida2',
            topologyVerdict: 'approximate',
            mappedNetwork: {
              'populations': [
                {'name': 'sensor'},
                {'name': 'motor'},
              ],
              'connections': [
                {'source': 'sensor', 'target': 'motor'},
              ],
            },
            networkSummary: {
              'n_populations': 2,
              'n_neurons': 32,
              'n_connections': 1,
              'n_synapses': 32,
              'estimated_weight_bytes': 16,
            },
          ),
        ),
      );

      expect(find.text('Akida Deployability'), findsOneWidget);
      expect(find.text('AKIDA2'), findsOneWidget);
      expect(find.textContaining('Topology verdict'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open in Neurochip Akida Flow'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open in Neurochip Akida Flow'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Mapped Output'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mapped Output'), findsOneWidget);
    });

    testWidgets('shows unsupported badge and rejections', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          const AkidaDeployState(
            phase: AkidaDeployPhase.unsupported,
            rejections: ['Branching topology is not supported on akida1.'],
          ),
        ),
      );

      expect(find.text('UNSUPPORTED'), findsOneWidget);
      expect(
        find.text('Branching topology is not supported on akida1.'),
        findsOneWidget,
      );
    });
  });
}
