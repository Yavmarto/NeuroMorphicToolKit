import 'dart:io';

import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Runs native desktop deployment commands without a coordinator service.
class LocalDeploymentService {
  const LocalDeploymentService();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  Future<Directory> materializeAssets(AssetBundle assets) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'deployment'));
    await directory.create(recursive: true);
    for (final relative in DeploymentAssetBundle.assetFiles) {
      final file = File(path.join(directory.path, relative));
      await file.parent.create(recursive: true);
      final data = await assets.load('assets/deployment/$relative');
      await file.writeAsBytes(
        DeploymentAssetBundle.exactBytes(data),
        flush: true,
      );
    }
    return directory;
  }

  Future<void> runChecked(
    String executable,
    List<String> arguments,
    Directory directory, {
    required int launcherControlPort,
    bool allowFailure = false,
  }) async {
    final result = await run(
      executable,
      arguments,
      workingDirectory: directory.path,
      environment: {
        ...Platform.environment,
        'SUITE_API_PORT': '9000',
        'LAUNCHER_CONTROL_PORT': '$launcherControlPort',
        'NMTK_IMAGE_TAG': 'latest',
      },
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError(
        '$executable ${arguments.join(' ')} failed: '
        '${result.stderr.toString().trim()}',
      );
    }
  }

  /// Materializes the deployment bundle and brings up local backend
  /// containers for [request], reporting progress through [emit]. Does not
  /// verify readiness afterward — the caller drives that with a
  /// `DeploymentHealthChecker`.
  Future<void> deploy(
    DeploymentJob job,
    DeploymentRequest request, {
    required AssetBundle assets,
    required int launcherControlPort,
    required Future<void> Function(
      DeploymentJob job,
      DeploymentPhase phase,
      double percent,
      String label,
    )
    emit,
  }) async {
    if (request.mode == 'standalone') {
      await emit(
        job,
        DeploymentPhase.completed,
        100,
        'Standalone backend target is configured',
      );
      return;
    }
    final directory = await materializeAssets(assets);
    final compose = <String>[
      'compose',
      '--project-name',
      'nmtk',
      '-f',
      'docker-compose.yml',
      '-f',
      'docker-compose.prod.yml',
    ];
    if (request.cleanInstall) {
      await runChecked(
        request.containerEngine,
        [...compose, 'down', '-v', '--remove-orphans'],
        directory,
        launcherControlPort: launcherControlPort,
        allowFailure: true,
      );
    }
    await emit(job, DeploymentPhase.pullingImages, 45, 'Pulling images');
    await runChecked(
      request.containerEngine,
      [...compose, 'pull'],
      directory,
      launcherControlPort: launcherControlPort,
    );
    await emit(
      job,
      DeploymentPhase.startingContainers,
      80,
      'Starting backend containers',
    );
    await runChecked(
      request.containerEngine,
      [...compose, 'up', '-d', '--no-build', '--remove-orphans'],
      directory,
      launcherControlPort: launcherControlPort,
    );
  }
}
