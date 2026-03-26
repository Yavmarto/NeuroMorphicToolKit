// ignore_for_file: avoid_print, unawaited_futures
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

/// This script tests the ProcessManager's ability to install and launch a module.
/// It must be run from the nmtk/neuro_toolkit directory.
void main() async {
  // Use a longer timeout for real installations
  const testTimeout = Timeout(Duration(minutes: 5));

  test('E2E Launcher Flow Test', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock path_provider for ProcessManager state saving
    final tempDir = Directory.systemTemp.createTempSync('nmtk_e2e_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory' ||
            methodCall.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    print('🚀 Starting E2E Launcher Flow Test...');

    // 1. Setup paths
    final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
    print('📍 Repo root: $repoRoot');

    // Define neurocnl module for testing
    final neurocnl = Module(
      id: 'neurocnl',
      name: 'CNL Studio',
      description: 'CNL parser',
      directory: p.join(repoRoot, 'neurocnl'),
      port: 8000,
      sourcePath: '.',
      runPath: '.',
      uvicornTarget: 'backend.app.main:app',
      localDeps: ['Neuro-Dream-Hand'],
    );

    final manager = ProcessManager();
    await manager.init([neurocnl]);

    final completer = Completer<void>();
    Module? lastStatus;

    final subscription = manager.statusUpdates.listen((Module updated) {
      print('🔄 [${updated.id}] Status: ${updated.status} Progress: ${updated.installProgress}');
      if (updated.id == 'neurocnl') {
        lastStatus = updated;
        if (!completer.isCompleted) {
          if (updated.status == ModuleStatus.starting || updated.status == ModuleStatus.running) {
            print('✅ neurocnl is STARTING/RUNNING!');
            completer.complete();
          } else if (updated.status == ModuleStatus.error) {
            print('❌ neurocnl entered ERROR state: ${updated.healthStatus}');
            completer.completeError(Exception('Module error: ${updated.healthStatus}'));
          }
        }
      }
    });

    try {
      // 2. Install
      print('📦 Installing neurocnl...');
      await manager.installModule(neurocnl, onProgress: (double p) {
        // progress printed via subscription
      });

      // Verify venv was created
      final venvPath = p.join(neurocnl.directory, neurocnl.sourcePath, 'venv');
      expect(Directory(venvPath).existsSync(), isTrue, reason: 'venv directory should exist');

      final pythonBin = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      expect(File(pythonBin).existsSync(), isTrue, reason: 'python binary should exist in venv');

      // 3. Start
      print('⚡ Starting neurocnl...');
      unawaited(manager.startModule(neurocnl));

      // Wait for running state or timeout (completer handled in subscription)
      await completer.future.timeout(const Duration(minutes: 3));

      expect(lastStatus?.status, anyOf(ModuleStatus.starting, ModuleStatus.running));

      // 4. Multi-module test: Start Neurosim
      print('📦 Installing Neurosim...');
      final neurosim = Module(
        id: 'Neurosim',
        name: 'NeuroSim',
        description: 'Visual design',
        directory: p.join(repoRoot, 'Neurosim'),
        port: 8001,
        sourcePath: '.',
        runPath: 'neurosim',
        uvicornTarget: 'app.main:app',
      );
      // We don't re-init manager as it's a singleton, but we make sure it knows about Neurosim
      // Actually manager.init just loads states and starts health polling.
      // manager.installModule and manager.startModule should work if we pass the module.

      await manager.installModule(neurosim);

      // Verify Neurosim venv
      final nsVenvPath = p.join(neurosim.directory, neurosim.sourcePath, 'venv');
      expect(Directory(nsVenvPath).existsSync(), isTrue, reason: 'Neurosim venv directory should exist');

      print('⚡ Starting Neurosim...');
      unawaited(manager.startModule(neurosim));

      // Wait for Neurosim to be running
      final neurosimCompleter = Completer<void>();
      final nsSub = manager.statusUpdates.listen((Module updated) {
        if (updated.id == 'Neurosim' && (updated.status == ModuleStatus.running || updated.status == ModuleStatus.starting)) {
          print('✅ Neurosim is STARTING/RUNNING!');
          if (!neurosimCompleter.isCompleted) neurosimCompleter.complete();
        }
      });

      await neurosimCompleter.future.timeout(const Duration(minutes: 2));
      await nsSub.cancel();

      // 5. Stop modules
      print('🛑 Stopping neurocnl...');
      await manager.stopModule('neurocnl');

      print('🛑 Stopping Neurosim...');
      await manager.stopModule('Neurosim');

      print('🎉 E2E Launcher Flow Test PASSED!');
    } catch (e) {
      print('💥 Test FAILED: $e');
      if (lastStatus?.healthStatus != null) {
        print('Last health status: ${lastStatus?.healthStatus}');
      }
      rethrow;
    } finally {
      await subscription.cancel();
      manager.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: testTimeout);
}
