import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:provider/provider.dart';

import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/screens/pynq_deploy_screen.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

class _NopPynqDeployService extends PynqDeployService {
  Completer<PynqPairedBoard>? provisionCompleter;

  @override
  Future<List<PynqPairedBoard>> fetchPairedBoards() async {
    return const <PynqPairedBoard>[
      PynqPairedBoard(
        id: 'board-1',
        displayName: 'Desk PYNQ',
        host: '192.168.1.50',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        credentialRef: '',
        runtimeApiUrl: 'http://192.168.1.50:8002',
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: 'ok',
        lastPreflightMessage: 'Ready',
        lastRuntimeMode: 'hardware',
        hasPassword: true,
        sshKeyPath: '',
      ),
    ];
  }

  @override
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    return const PynqNetworkResponse(
      supportState: PynqSupportState.exportable,
      warnings: <String>[],
      rejectionReasons: <String>[],
      deployPayload: PynqDeployPayload(
        weights: <double>[1.0, 2.0],
        config: PynqDeployConfig(
          threshold: 1.0,
          bitWidth: 4,
          scaleFactor: 7.0,
        ),
        bitstreamPath: 'snn_overlay.bit',
        registerMap: PynqRegisterMap(
          baseAddress: 0x40000000,
          controlRegOffset: 0x00,
          statusRegOffset: 0x04,
          neuronBaseOffset: 0x100,
          weightBaseOffset: 0x10000,
          dmaChannel: 'axi_dma_0',
          inputBufferAddr: 0,
          outputBufferAddr: 0,
          timestepUs: 1000,
        ),
      ),
    );
  }

  @override
  Future<PynqPairedBoard> provisionBoard({
    required String boardId,
  }) async {
    if (provisionCompleter != null) {
      return provisionCompleter!.future;
    }
    return const PynqPairedBoard(
      id: 'board-1',
      displayName: 'Desk PYNQ',
      host: '192.168.1.50',
      sshPort: 22,
      username: 'xilinx',
      authMode: PynqBoardAuthMode.password,
      credentialRef: '',
      runtimeApiUrl: 'http://192.168.1.50:8002',
      overlayVersion: '',
      state: PynqBoardState.ready,
      lastPreflightStatus: 'ok',
      lastPreflightMessage: 'Ready',
      lastRuntimeMode: 'hardware',
      hasPassword: true,
      sshKeyPath: '',
    );
  }

  @override
  void dispose() {}
}

Widget _buildTestApp(PynqDeployProvider provider) {
  return MaterialApp(
    home: ChangeNotifierProvider<PynqDeployProvider>.value(
      value: provider,
      child: const PynqDeployScreen(),
    ),
  );
}

void main() {
  group('PynqDeployScreen', () {
    testWidgets('renders stepper and paired board controls', (tester) async {
      final provider = PynqDeployProvider(service: _NopPynqDeployService());
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Paired Board'), findsOneWidget);
      expect(find.text('Provision Runtime'), findsOneWidget);
      expect(find.text('Check Readiness'), findsOneWidget);
    });

    testWidgets('shows deployment package after exportability check',
        (tester) async {
      final provider = PynqDeployProvider(service: _NopPynqDeployService());
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );
      await tester.pump();

      expect(find.text('Deployment Package'), findsOneWidget);
      expect(find.textContaining('2 packed weights'), findsOneWidget);
      expect(find.text('Deploy And Verify'), findsOneWidget);
    });

    testWidgets('shows board activity feedback while provisioning',
        (tester) async {
      final service = _NopPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.provisionCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await tester.ensureVisible(find.text('Provision Runtime'));
      await tester.tap(find.text('Provision Runtime'));
      await tester.pump();

      expect(find.textContaining('Provisioning runtime'), findsWidgets);
      expect(find.text('Provisioning...'), findsOneWidget);

      completer.complete(
        const PynqPairedBoard(
          id: 'board-1',
          displayName: 'Desk PYNQ',
          host: '192.168.1.50',
          sshPort: 22,
          username: 'xilinx',
          authMode: PynqBoardAuthMode.password,
          credentialRef: '',
          runtimeApiUrl: 'http://192.168.1.50:8002',
          overlayVersion: '',
          state: PynqBoardState.ready,
          lastPreflightStatus: 'ok',
          lastPreflightMessage: 'Ready',
          lastRuntimeMode: 'hardware',
          hasPassword: true,
          sshKeyPath: '',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Runtime provisioning finished'), findsWidgets);
    });
  });
}
