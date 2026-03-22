import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

/// This script tests the ProcessManager's ability to install and launch a module.
/// It must be run from the nmtk/neuro_toolkit directory.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final subscription = manager.statusUpdates.listen((updated) {
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
    await manager.installModule(neurocnl, onProgress: (p) {
      // progress printed via subscription
    });

    // 3. Start
    print('⚡ Starting neurocnl...');
    await manager.startModule(neurocnl);

    // Wait for running state or timeout
    await completer.future.timeout(const Duration(minutes: 2));

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
    await manager.init([neurocnl, neurosim]);
    await manager.installModule(neurosim);

    print('⚡ Starting Neurosim...');
    await manager.startModule(neurosim);

    // Wait for Neurosim to be running
    final neurosimCompleter = Completer<void>();
    final nsSub = manager.statusUpdates.listen((updated) {
      if (updated.id == 'Neurosim' && (updated.status == ModuleStatus.running || updated.status == ModuleStatus.starting)) {
        print('✅ Neurosim is STARTING/RUNNING!');
        neurosimCompleter.complete();
      }
    });

    await neurosimCompleter.future.timeout(const Duration(minutes: 2));
    nsSub.cancel();

    // 5. Stop modules
    print('🛑 Stopping neurocnl...');
    await manager.stopModule('neurocnl');

    // Give it a moment to stop
    await Future.delayed(const Duration(seconds: 2));

    print('🎉 E2E Launcher Flow Test PASSED!');
    exit(0);
  } catch (e) {
    print('💥 Test FAILED: $e');
    if (lastStatus?.healthStatus != null) {
      print('Last health status: ${lastStatus?.healthStatus}');
    }
    // Try to cleanup
    await manager.stopModule('neurocnl');
    exit(1);
  } finally {
    subscription.cancel();
    manager.dispose();
  }
}
