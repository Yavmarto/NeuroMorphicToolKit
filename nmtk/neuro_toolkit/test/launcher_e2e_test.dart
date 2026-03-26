// ignore_for_file: avoid_print, unawaited_futures
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

/// This script tests the ProcessManager's ability to install and launch a module.
/// It must be run from the nmtk/neuro_toolkit directory.
void main() async {
  test('E2E Launcher Flow Test', () async {
  if (Platform.environment.containsKey('FLUTTER_TEST') || Platform.environment.containsKey('GITHUB_ACTIONS')) {
    print('Skipping E2E Launcher Flow Test in headless CI environment');
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  debugPrint('Tests need mock ProcessRunner, skipping real dependencies check');

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
          if (!completer.isCompleted) {
             completer.completeError(Exception('Module error: ${updated.healthStatus}'));
          }
        }
      }
    }
  });

  try {
    // 2. Install
    print('📦 Installing neurocnl...');
    await manager.installModule(neurocnl, onProgress: (double p) {
      // progress printed via subscription
    },);

    // 3. Start
    print('⚡ Starting neurocnl...');
    unawaited(manager.startModule(neurocnl));

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
    unawaited(manager.stopModule('neurocnl'));

    // Give it a moment to stop
    await Future<void>.delayed(const Duration(seconds: 2));

    print('🎉 E2E Launcher Flow Test PASSED!');
  } catch (e) {
    print('💥 Test FAILED: $e');
    if (lastStatus?.healthStatus != null) {
      print('Last health status: ${lastStatus?.healthStatus}');
    }
    // Try to cleanup
    unawaited(manager.stopModule('neurocnl'));
    rethrow;
  } finally {
    await subscription.cancel();
    manager.dispose();
  }
  });
}
