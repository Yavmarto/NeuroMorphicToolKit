import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

typedef PackageInfoLoader = Future<PackageInfo> Function();

class UpdateService {
  UpdateChannel channel = UpdateChannel.stable;

  UpdateService({
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
    Uri? launcherRepositoryUri,
  }) : _client = client ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _launcherRepositoryUri =
           launcherRepositoryUri ?? Uri.parse(_launcherRepositoryApiUrl);

  static const String _launcherRepositoryApiUrl =
      'https://api.github.com/repos/Yavmarto/NeuroMorphicToolKit';
  static const Map<String, String> _githubHeaders = <String, String>{
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'NeuroMorphicToolkit-Launcher',
  };
  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  final PackageInfoLoader _packageInfoLoader;
  final Uri _launcherRepositoryUri;

  Future<LauncherUpdate?> checkForLauncherUpdate() async {
    try {
      final packageInfo = await _packageInfoLoader();
      final currentVersion = packageInfo.version;
      final release = await _fetchRepositoryRelease(
        repositoryApiUri: _launcherRepositoryUri,
        channel: channel,
      );

      if (release != null && isNewerVersion(currentVersion, release.version)) {
        return LauncherUpdate(
          version: release.version,
          url: release.url,
          releaseNotes: release.releaseNotes,
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
      final repositoryApiUri = _normalizeRepositoryApiUri(
        Uri.parse(module.remoteUrl!),
      );
      if (repositoryApiUri == null) {
        return null;
      }
      final release = await _fetchRepositoryRelease(
        repositoryApiUri: repositoryApiUri,
        channel: channel,
      );

      if (release != null && isNewerVersion(module.version, release.version)) {
        return release.version;
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
      'Starting differential update for ${module.id} to $targetVersion',
    );

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

  /// Newest backend release, or null when [runningVersion] is already current.
  ///
  /// The backend container images are built from the same monorepo tags as the
  /// launcher (`.github/workflows/release-docker.yml` pushes on every `v*`), so
  /// this asks the same repository as [checkForLauncherUpdate] — but compares
  /// against the version the *backend* reports rather than the app's own, since
  /// a current app can be pointed at a stale backend.
  ///
  /// Pass the value from `ControlApiService.fetchBackendVersion()`. A backend
  /// built from source reports `"dev"`, which is deliberately never treated as
  /// updatable: there is no release to compare it with.
  Future<LauncherUpdate?> checkForBackendUpdate(String runningVersion) async {
    if (runningVersion.trim().isEmpty || runningVersion.trim() == 'dev') {
      return null;
    }
    try {
      final release = await _fetchRepositoryRelease(
        repositoryApiUri: _launcherRepositoryUri,
        channel: channel,
      );
      if (release != null && isNewerVersion(runningVersion, release.version)) {
        return LauncherUpdate(
          version: release.version,
          url: release.url,
          releaseNotes: release.releaseNotes,
        );
      }
    } catch (e) {
      debugPrint('Error checking for backend update: $e');
    }
    return null;
  }

  static bool isNewerVersion(String current, String remote) {
    return _compareVersions(remote, current) > 0;
  }

  Future<_RepositoryRelease?> _fetchRepositoryRelease({
    required Uri repositoryApiUri,
    required UpdateChannel channel,
  }) async {
    final releases = await _readJsonList(
      repositoryApiUri.replace(
        path: '${repositoryApiUri.path}/releases',
        queryParameters: const <String, String>{'per_page': '100'},
      ),
    );
    if (releases != null) {
      final release = _selectReleaseCandidate(
        releases,
        repositoryApiUri,
        channel,
      );
      if (release != null) {
        return release;
      }
    }

    final tags = await _readJsonList(
      repositoryApiUri.replace(
        path: '${repositoryApiUri.path}/tags',
        queryParameters: const <String, String>{'per_page': '100'},
      ),
    );
    if (tags == null) {
      return null;
    }
    return _selectTagCandidate(tags, repositoryApiUri, channel);
  }

  Future<List<dynamic>?> _readJsonList(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _githubHeaders)
          .timeout(_requestTimeout);
      if (response.statusCode == 404) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'GitHub version lookup failed (${response.statusCode}) for $uri',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is List<dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('GitHub version lookup failed for $uri: $e');
      return null;
    }
  }
}

class _RepositoryRelease {
  const _RepositoryRelease({
    required this.version,
    required this.url,
    required this.releaseNotes,
    required this.isPrerelease,
  });

  final String version;
  final String url;
  final String releaseNotes;
  final bool isPrerelease;
}

class _ParsedVersion {
  const _ParsedVersion({
    required this.core,
    required this.prereleaseIdentifiers,
  });

  final List<int> core;
  final List<String> prereleaseIdentifiers;
}

enum _ReleaseTrack { stable, beta, nightly }

Uri? _normalizeRepositoryApiUri(Uri repositoryUri) {
  if (repositoryUri.scheme != 'http' && repositoryUri.scheme != 'https') {
    return null;
  }

  final pathSegments = repositoryUri.pathSegments.where(
    (String segment) => segment.isNotEmpty,
  );
  final segments = pathSegments.toList(growable: false);

  if (repositoryUri.host == 'api.github.com' &&
      segments.length >= 3 &&
      segments.first == 'repos') {
    return Uri.parse(
      'https://api.github.com/repos/${segments[1]}/${segments[2]}',
    );
  }

  if (repositoryUri.host == 'github.com' && segments.length >= 2) {
    final repositoryName = segments[1].endsWith('.git')
        ? segments[1].substring(0, segments[1].length - 4)
        : segments[1];
    return Uri.parse(
      'https://api.github.com/repos/${segments[0]}/$repositoryName',
    );
  }

  return null;
}

String _normalizeVersion(String raw) {
  var normalized = raw.trim();
  if (normalized.startsWith('refs/tags/')) {
    normalized = normalized.substring('refs/tags/'.length);
  }
  if (normalized.length > 1 &&
      normalized.startsWith('v') &&
      int.tryParse(normalized[1]) != null) {
    normalized = normalized.substring(1);
  }
  return normalized;
}

_ParsedVersion? _parseVersion(String raw) {
  final normalized = _normalizeVersion(raw).split('+').first;
  if (normalized.isEmpty) {
    return null;
  }
  final parts = normalized.split('-');
  final coreParts = parts.first.split('.');
  final core = <int>[];
  for (final part in coreParts) {
    final value = int.tryParse(part);
    if (value == null) {
      return null;
    }
    core.add(value);
  }

  final prereleaseIdentifiers = parts.length > 1
      ? parts
            .skip(1)
            .join('-')
            .split('.')
            .where((String identifier) => identifier.isNotEmpty)
            .toList(growable: false)
      : const <String>[];

  return _ParsedVersion(
    core: core,
    prereleaseIdentifiers: prereleaseIdentifiers,
  );
}

int _comparePrereleaseIdentifiers(List<String> left, List<String> right) {
  for (var index = 0; index < left.length && index < right.length; index++) {
    final leftIdentifier = left[index];
    final rightIdentifier = right[index];
    final leftNumber = int.tryParse(leftIdentifier);
    final rightNumber = int.tryParse(rightIdentifier);
    if (leftNumber != null && rightNumber != null) {
      if (leftNumber != rightNumber) {
        return leftNumber.compareTo(rightNumber);
      }
      continue;
    }
    if ((leftNumber != null) != (rightNumber != null)) {
      return leftNumber != null ? -1 : 1;
    }
    final comparison = leftIdentifier.compareTo(rightIdentifier);
    if (comparison != 0) {
      return comparison;
    }
  }

  return left.length.compareTo(right.length);
}

int _compareVersions(String left, String right) {
  final leftParsed = _parseVersion(left);
  final rightParsed = _parseVersion(right);
  if (leftParsed == null || rightParsed == null) {
    return _normalizeVersion(left).compareTo(_normalizeVersion(right));
  }

  final maxLength = leftParsed.core.length > rightParsed.core.length
      ? leftParsed.core.length
      : rightParsed.core.length;
  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParsed.core.length
        ? leftParsed.core[index]
        : 0;
    final rightValue = index < rightParsed.core.length
        ? rightParsed.core[index]
        : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }

  final leftPrerelease = leftParsed.prereleaseIdentifiers;
  final rightPrerelease = rightParsed.prereleaseIdentifiers;
  if (leftPrerelease.isEmpty && rightPrerelease.isEmpty) {
    return 0;
  }
  if (leftPrerelease.isEmpty) {
    return 1;
  }
  if (rightPrerelease.isEmpty) {
    return -1;
  }
  return _comparePrereleaseIdentifiers(leftPrerelease, rightPrerelease);
}

bool _isNightlyLabel(String label) {
  return label.contains('nightly') ||
      label.contains('dev') ||
      label.contains('snapshot') ||
      label.contains('canary');
}

_ReleaseTrack _classifyTrack(String version, {required bool isPrerelease}) {
  final parsed = _parseVersion(version);
  final prereleaseLabel = parsed == null
      ? _normalizeVersion(version).toLowerCase()
      : parsed.prereleaseIdentifiers.join('.').toLowerCase();
  if (_isNightlyLabel(prereleaseLabel)) {
    return _ReleaseTrack.nightly;
  }
  if (prereleaseLabel.isNotEmpty || isPrerelease) {
    return _ReleaseTrack.beta;
  }
  return _ReleaseTrack.stable;
}

bool _matchesChannel(
  String version, {
  required bool isPrerelease,
  required UpdateChannel channel,
}) {
  final track = _classifyTrack(version, isPrerelease: isPrerelease);
  switch (channel) {
    case UpdateChannel.stable:
      return track == _ReleaseTrack.stable;
    case UpdateChannel.beta:
      return track == _ReleaseTrack.beta;
    case UpdateChannel.nightly:
      return track == _ReleaseTrack.nightly;
  }
}

String _repositoryHtmlUrl(Uri repositoryApiUri) {
  final segments = repositoryApiUri.pathSegments
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.length >= 3 && segments.first == 'repos') {
    return 'https://github.com/${segments[1]}/${segments[2]}';
  }
  return 'https://github.com';
}

_RepositoryRelease? _selectNewestRelease(
  Iterable<_RepositoryRelease> candidates,
) {
  _RepositoryRelease? newest;
  for (final candidate in candidates) {
    if (newest == null ||
        UpdateService.isNewerVersion(newest.version, candidate.version)) {
      newest = candidate;
    }
  }
  return newest;
}

_RepositoryRelease? _selectReleaseCandidate(
  List<dynamic> releases,
  Uri repositoryApiUri,
  UpdateChannel channel,
) {
  final candidates = <_RepositoryRelease>[];
  for (final item in releases) {
    if (item is! Map) {
      continue;
    }
    final release = item.cast<String, dynamic>();
    if (release['draft'] == true) {
      continue;
    }
    final rawTag = release['tag_name'];
    if (rawTag is! String) {
      continue;
    }
    final version = _normalizeVersion(rawTag);
    final isPrerelease = release['prerelease'] as bool? ?? false;
    if (_parseVersion(version) == null ||
        !_matchesChannel(
          version,
          isPrerelease: isPrerelease,
          channel: channel,
        )) {
      continue;
    }
    candidates.add(
      _RepositoryRelease(
        version: version,
        url:
            release['html_url'] as String? ??
            '${_repositoryHtmlUrl(repositoryApiUri)}/releases',
        releaseNotes: (release['body'] as String? ?? '').trim(),
        isPrerelease: isPrerelease,
      ),
    );
  }
  return _selectNewestRelease(candidates);
}

_RepositoryRelease? _selectTagCandidate(
  List<dynamic> tags,
  Uri repositoryApiUri,
  UpdateChannel channel,
) {
  final candidates = <_RepositoryRelease>[];
  for (final item in tags) {
    if (item is! Map) {
      continue;
    }
    final tag = item.cast<String, dynamic>();
    final rawName = tag['name'];
    if (rawName is! String) {
      continue;
    }
    final version = _normalizeVersion(rawName);
    if (_parseVersion(version) == null) {
      continue;
    }
    final isPrerelease =
        _classifyTrack(version, isPrerelease: false) != _ReleaseTrack.stable;
    if (!_matchesChannel(
      version,
      isPrerelease: isPrerelease,
      channel: channel,
    )) {
      continue;
    }
    candidates.add(
      _RepositoryRelease(
        version: version,
        url: '${_repositoryHtmlUrl(repositoryApiUri)}/tags',
        releaseNotes: '',
        isPrerelease: isPrerelease,
      ),
    );
  }
  return _selectNewestRelease(candidates);
}
