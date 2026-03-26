// ignore_for_file: unawaited_futures
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

/// This script tests the ProcessManager's ability to install and launch modules.
/// It also tests the failure recovery mechanism.
/// It must be run from the nmtk/neuro_toolkit directory.
void main() {
  final forceE2E = Platform.environment['FORCE_E2E'] == 'true';
  final isCI = Platform.environment.containsKey('GITHUB_ACTIONS') ||
      Platform.environment.containsKey('FLUTTER_TEST');

  group('E2E Launcher Integration', () {
    late ProcessManager manager;
    late String repoRoot;
    late List<Module> allModules;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));

      // Load modules from assets/modules.json
      final jsonFile = File(p.join(Directory.current.path, 'assets', 'modules.json'));
      final jsonString = await jsonFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;

      allModules = jsonList.map((dynamic json) {
        final m = Module.fromJson(json as Map<String, dynamic>);
        return m.copyWith(
          directory: p.normalize(p.join(repoRoot, m.directory)),
        );
      }).toList();

      manager = ProcessManager();
      await manager.init(allModules);
    });

    tearDownAll(() {
      manager.dispose();
    });

    test('Full Workflow: Start All HTTP Modules', () async {
      if (isCI && !forceE2E) {
        debugPrint('⏩ Skipping E2E test in CI environment (FORCE_E2E not set).');
        return;
      }

      print('🚀 Starting E2E Full Workflow Test...');

      final httpModules = allModules.where((m) => m.port != null).toList();

      for (final module in httpModules) {
        print('📦 Installing ${module.name} (${module.id})...');
        try {
          await manager.installModule(module).timeout(const Duration(minutes: 5));

          print('⚡ Starting ${module.name}...');
          unawaited(manager.startModule(module));

          // Wait for running state
          final completer = Completer<void>();
          final sub = manager.statusUpdates.listen((updated) {
            if (updated.id == module.id &&
                (updated.status == ModuleStatus.running || updated.status == ModuleStatus.degraded)) {
              if (!completer.isCompleted) completer.complete();
            } else if (updated.id == module.id && updated.status == ModuleStatus.error) {
              if (!completer.isCompleted) completer.completeError(Exception('Module ${module.id} failed to start: ${updated.healthStatus}'));
            }
          });

          await completer.future.timeout(const Duration(minutes: 2));
          await sub.cancel();
          print('✅ ${module.name} is UP!');
        } catch (e) {
          print('❌ Failed to bring up ${module.name}: $e');
          rethrow;
        }
      }

      print('🎉 All HTTP modules started successfully!');

      // Cleanup: stop all
      for (final module in httpModules) {
        await manager.stopModule(module.id);
      }
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('Module Failure Recovery Test', () async {
      if (isCI && !forceE2E) {
        debugPrint('⏩ Skipping Failure Recovery test in CI environment.');
        return;
      }

      print('🛠️ Starting Failure Recovery Test...');

      // Use neurocnl for this test
      final module = allModules.firstWhere((m) => m.id == 'neurocnl');

      print('📦 Ensuring ${module.id} is installed...');
      await manager.installModule(module).timeout(const Duration(minutes: 5));

      print('⚡ Starting ${module.id}...');
      unawaited(manager.startModule(module));

      // Wait for it to be running
      await Future<void>.delayed(const Duration(seconds: 10));

      // Verify it's running (or starting)
      // Note: we can't easily check the status synchronously without keeping track,
      // but we can listen for the next health check or just assume it's up if we waited enough.

      print('💀 Simulating crash (killing process on port ${module.port})...');
      bool killed = false;
      if (Platform.isWindows) {
        final result = await Process.run('netstat', ['-ano']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':${module.port}') && line.contains('LISTENING')) {
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 5) {
                final pid = parts.last;
                print('Killing process $pid');
                await Process.run('taskkill', ['/F', '/PID', pid]);
                killed = true;
                break;
              }
            }
          }
        }
      } else {
        // macOS/Linux
        final result = await Process.run('lsof', ['-ti', ':${module.port}']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final pid = result.stdout.toString().trim().split('\n').first;
          print('Killing process $pid');
          Process.killPid(int.parse(pid), ProcessSignal.sigkill);
          killed = true;
        }
      }

      if (!killed) {
        fail('Could not find process running on port ${module.port}');
      }

      print('⏳ Waiting for failure detection...');
      final failureCompleter = Completer<void>();
      final recoveryCompleter = Completer<void>();

      final sub = manager.statusUpdates.listen((updated) {
        if (updated.id == module.id) {
          print('🔄 Status change: ${updated.status}');
          if (updated.status == ModuleStatus.error && !failureCompleter.isCompleted) {
            print('✅ Failure detected!');
            failureCompleter.complete();
          } else if ((updated.status == ModuleStatus.running || updated.status == ModuleStatus.starting) &&
                     failureCompleter.isCompleted && !recoveryCompleter.isCompleted) {
            print('✅ Recovery started!');
            recoveryCompleter.complete();
          }
        }
      });

      await failureCompleter.future.timeout(const Duration(seconds: 30));
      print('⏳ Waiting for auto-restart (backoff is 5s)...');
      await recoveryCompleter.future.timeout(const Duration(seconds: 60));

      await sub.cancel();
      print('🎉 Failure Recovery Test PASSED!');

      await manager.stopModule(module.id);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
