import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/pynq_deploy_panel.dart';

class MockPynqDeployController extends PynqDeployController {
  MockPynqDeployController(this._initialState);
  final PynqDeployState _initialState;

  @override
  PynqDeployState build() => _initialState;

  @override
  Future<void> validate(String spec) async {}

  @override
  void selectBitWidth(int bitWidth) {}
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

Widget buildWidget(PynqDeployState state, {String spec = 'spec'}) {
  return ProviderScope(
    overrides: [
      pynqDeployControllerProvider.overrideWith(
        () => MockPynqDeployController(state),
      ),
      specTextProvider.overrideWith(() => MockSpecTextController(spec)),
    ],
    child: const MaterialApp(home: Scaffold(body: PynqDeployPanel())),
  );
}

void main() {
  group('PynqDeployPanel', () {
    testWidgets('renders support state and network summary when ready', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(
          const PynqDeployState(
            phase: PynqDeployPhase.ready,
            supportState: PynqSupportState.exportable,
            networkSummary: {'n_neurons': 32, 'n_synapses': 256},
          ),
        ),
      );

      expect(find.text('PYNQ-Z2 Deployability'), findsOneWidget);
      expect(find.textContaining('Exportable'), findsOneWidget);
      expect(find.text('Run PYNQ Check'), findsOneWidget);
      expect(find.textContaining('overlay/bitstream'), findsWidgets);
    });

    testWidgets('shows rejections when not exportable', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          const PynqDeployState(
            phase: PynqDeployPhase.unsupported,
            supportState: PynqSupportState.notExportable,
            rejections: ['Synapse count exceeds the PYNQ Z2 overlay limit.'],
          ),
        ),
      );

      expect(find.textContaining('Not Exportable'), findsOneWidget);
      expect(
        find.textContaining('Synapse count exceeds the PYNQ Z2 overlay limit.'),
        findsOneWidget,
      );
    });

    testWidgets('shows idle placeholder before first check', (tester) async {
      await tester.pumpWidget(buildWidget(const PynqDeployState()));

      expect(find.text('No PYNQ-Z2 verdict yet.'), findsOneWidget);
    });
  });
}
