import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:neuro_toolkit/models/module.dart';

enum UpdateChannel { stable, beta, nightly }

class LauncherUpdate {
  final String version;
  final String url;
  final String releaseNotes;

  LauncherUpdate({
    required this.version,
    required this.url,
    required this.releaseNotes,
  });
}

class UpdateService {
  final http.Client _client;
  UpdateChannel _channel = UpdateChannel.stable;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  UpdateChannel get channel => _channel;
  set channel(UpdateChannel value) => _channel = value;

  Future<LauncherUpdate?> checkForLauncherUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Mock remote manifest fetch
      // In a real scenario, this would be an HTTP GET to a version file
      await Future<void>.delayed(const Duration(seconds: 1));

      // Mocking a newer version available for demo purposes
      // Usually we'd compare versions here
      const remoteVersion = '1.1.0';

      if (_isNewerVersion(currentVersion, remoteVersion)) {
        return LauncherUpdate(
          version: remoteVersion,
          url:
              'https://github.com/Completed-Spoon-6/NeuroMorphicToolkit/releases/latest',
          releaseNotes: 'Performance improvements and bug fixes.',
        );
      }
    } catch (e) {
      debugPrint('Error checking for launcher update: $e');
    }
    return null;
  }

  Future<String?> checkForModuleUpdate(Module module) async {
    if (module.versionPinned || module.remoteUrl == null) return null;

    try {
      // Mock remote module version check
      // In a real scenario, we might hit the GitHub API or a custom manifest
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Simulated remote versions based on channel
      String remoteVersion;
      switch (_channel) {
        case UpdateChannel.stable:
          remoteVersion = '1.0.1';
          break;
        case UpdateChannel.beta:
          remoteVersion = '1.1.0-beta';
          break;
        case UpdateChannel.nightly:
          remoteVersion = '1.1.0-nightly.${DateTime.now().day}';
          break;
      }

      if (_isNewerVersion(module.version, remoteVersion)) {
        return remoteVersion;
      }
    } catch (e) {
      debugPrint('Error checking for module update (${module.id}): $e');
    }
    return null;
  }

  Future<void> performDifferentialUpdate(
    Module module,
    String targetVersion, {
    void Function(double)? onProgress,
  }) async {
    // This is where we would implement differential updates (rsync-like logic or patch application)
    // For this task, we simulate the process

    debugPrint(
        'Starting differential update for ${module.id} to $targetVersion');

    // Simulate steps:
    // 1. Fetch manifest of changed files
    onProgress?.call(0.1);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 2. Download only changed files (mocked)
    for (var i = 2; i <= 9; i++) {
      onProgress?.call(i / 10.0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // 3. Verify and apply
    onProgress?.call(1.0);
    debugPrint('Differential update complete for ${module.id}');
  }

  bool _isNewerVersion(String current, String remote) {
    // Simple version comparison logic
    // In production, use a proper semver package
    try {
      final currentParts = current.split('+')[0].split('-')[0].split('.');
      final remoteParts = remote.split('+')[0].split('-')[0].split('.');

      for (var i = 0; i < 3; i++) {
        final c = i < currentParts.length ? int.parse(currentParts[i]) : 0;
        final r = i < remoteParts.length ? int.parse(remoteParts[i]) : 0;
        if (r > c) return true;
        if (c > r) return false;
      }

      // Handle beta/nightly tags (simpler version: any tag means different)
      if (remote.contains('-') && !current.contains('-')) return true;
    } catch (e) {
      return remote != current;
    }
    return false;
  }
}
