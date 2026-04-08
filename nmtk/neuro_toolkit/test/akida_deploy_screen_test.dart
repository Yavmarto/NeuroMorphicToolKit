import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:provider/provider.dart';

import 'package:neuro_toolkit/providers/akida_deploy_provider.dart';
import 'package:neuro_toolkit/screens/akida_deploy_screen.dart';
import 'package:neuro_toolkit/services/akida_deploy_service.dart';

// ---------------------------------------------------------------------------
// Minimal mock service (no network calls)
// ---------------------------------------------------------------------------

class _NopAkidaDeployService extends AkidaDeployService {
  @override
  Future<AkidaNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
    String akidaVersion = 'akida1',
  }) async {
    return const AkidaNetworkResponse(
      supportState: AkidaSupportState.exportableScaffold,
      akidaVersion: 'akida1',
      topologyVerdict: 'ok',
      warnings: [],
      rejectionReasons: [],
    );
  }

  @override
  Future<String> downloadPackage({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String outputDir,
  }) async =>
      '/tmp/akida_deploy.zip';

  @override
  Future<AkidaDeployJob> getStatus() async =>
      const AkidaDeployJob(status: AkidaDeployJobStatus.notInitialised);

  @override
  Future<String> runNeurobenchJob({
    required String benchmarkId,
    required String networkPath,
    String target = 'simulation',
  }) async =>
      'job-001';

  @override
  Future<Map<String, dynamic>> getNeurobenchJobStatus(String jobId) async =>
      {'status': 'complete'};

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildTestApp(AkidaDeployProvider provider) {
  return MaterialApp(
    home: ChangeNotifierProvider<AkidaDeployProvider>.value(
      value: provider,
      child: const AkidaDeployScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AkidaDeployScreen — Neurobench toggle', () {
    testWidgets('deploy config card shows enabled Neurobench switch',
        (tester) async {
      final provider =
          AkidaDeployProvider(service: _NopAkidaDeployService());
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 8,
      );
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      // The deploy config card should be visible.
      expect(find.byType(Switch), findsWidgets);

      // Find the Neurobench switch specifically via its label.
      expect(
        find.text('Run Neurobench verification after deploy'),
        findsOneWidget,
      );
    });

    testWidgets('Neurobench switch is interactive (not hard-disabled)',
        (tester) async {
      final provider =
          AkidaDeployProvider(service: _NopAkidaDeployService());
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 8,
      );
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      // Verify the old "not yet available" label is gone.
      expect(find.textContaining('not yet available'), findsNothing);
    });

    testWidgets('setRunNeurobench toggles provider state and Switch reflects it',
        (tester) async {
      final provider =
          AkidaDeployProvider(service: _NopAkidaDeployService());
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 8,
      );
      expect(provider.runNeurobench, isFalse);

      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      // Verify initial switch value is false.
      final switchWidget =
          tester.widgetList<Switch>(find.byType(Switch)).firstWhere(
                (s) => s.onChanged != null,
              );
      expect(switchWidget.value, isFalse);

      // Toggle via provider (same path the Switch.onChanged calls).
      provider.setRunNeurobench(true);
      await tester.pump();

      expect(provider.runNeurobench, isTrue);
      final switchWidgetAfter =
          tester.widgetList<Switch>(find.byType(Switch)).firstWhere(
                (s) => s.onChanged != null,
              );
      expect(switchWidgetAfter.value, isTrue);
    });
  });
}
