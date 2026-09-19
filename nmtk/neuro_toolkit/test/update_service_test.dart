import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('returns false for downgrades', () {
      expect(UpdateService.isNewerVersion('1.0.0', '0.5.0'), isFalse);
    });

    test('treats stable releases as newer than matching prereleases', () {
      expect(UpdateService.isNewerVersion('1.0.0-beta.2', '1.0.0'), isTrue);
    });
  });

  group('UpdateService repository lookups', () {
    test('uses tag metadata when stable releases are not published', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response('[]', 200);
          }
          if (request.url.path.endsWith('/tags')) {
            return http.Response(
              jsonEncode(<Map<String, String>>[
                <String, String>{'name': 'v1.2.0'},
                <String, String>{'name': 'v1.1.0'},
              ]),
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      final update = await service.checkForLauncherUpdate();

      expect(update, isNotNull);
      expect(update!.version, '1.2.0');
      expect(update.url, contains('/tags'));
    });

    test('returns null when launcher metadata lookup fails offline', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          throw http.ClientException('offline');
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      final update = await service.checkForLauncherUpdate();

      expect(update, isNull);
    });

    test('offers nothing when the repository has no releases or tags yet', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          // A freshly published repository returns empty lists for both
          // endpoints until the first release/tag lands.
          return http.Response('[]', 200);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      expect(await service.checkForLauncherUpdate(), isNull);
    });

    test('returns null for a module whose remote repository is not public', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          return http.Response('Not Found', 404);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );
      final module = Module(
        id: 'neurocnl',
        name: 'NeuroCNL',
        description: 'Remote module',
        directory: 'neurocnl',
        version: '1.0.0',
        remoteUrl: 'https://api.github.com/repos/Yavmarto/neurocnl',
      );

      expect(await service.checkForModuleUpdate(module), isNull);
    });

    test('skips pinned modules without performing a lookup', () async {
      var requestCount = 0;
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          requestCount += 1;
          return http.Response('[]', 200);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );
      final module = Module(
        id: 'dummy',
        name: 'Dummy',
        description: 'Pinned module',
        directory: 'dummy',
        version: '1.0.0',
        versionPinned: true,
        remoteUrl: 'https://api.github.com/repos/example/dummy',
      );

      final update = await service.checkForModuleUpdate(module);

      expect(update, isNull);
      expect(requestCount, 0);
    });

    test('selects beta releases for the beta channel', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'tag_name': '1.2.0-beta.1',
                  'html_url':
                      'https://github.com/example/dummy/releases/tag/1.2.0-beta.1',
                  'body': 'Beta release',
                  'draft': false,
                  'prerelease': true,
                },
                <String, Object?>{
                  'tag_name': '1.1.0',
                  'html_url':
                      'https://github.com/example/dummy/releases/tag/1.1.0',
                  'body': 'Stable release',
                  'draft': false,
                  'prerelease': false,
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      )..channel = UpdateChannel.beta;
      final module = Module(
        id: 'dummy',
        name: 'Dummy',
        description: 'Beta module',
        directory: 'dummy',
        version: '1.1.0',
        remoteUrl: 'https://api.github.com/repos/example/dummy',
      );

      final update = await service.checkForModuleUpdate(module);

      expect(update, '1.2.0-beta.1');
    });

    test('selects nightly tags for the nightly channel', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response('[]', 200);
          }
          if (request.url.path.endsWith('/tags')) {
            return http.Response(
              jsonEncode(<Map<String, String>>[
                <String, String>{'name': '1.2.0'},
                <String, String>{'name': '1.2.0-beta.2'},
                <String, String>{'name': '1.2.0-nightly.5'},
              ]),
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      )..channel = UpdateChannel.nightly;
      final module = Module(
        id: 'dummy',
        name: 'Dummy',
        description: 'Nightly module',
        directory: 'dummy',
        version: '1.2.0-nightly.4',
        remoteUrl: 'https://api.github.com/repos/example/dummy',
      );

      final update = await service.checkForModuleUpdate(module);

      expect(update, '1.2.0-nightly.5');
    });
  });

  group('UpdateService.checkForBackendUpdate', () {
    UpdateService serviceReturning(String latestTag) => UpdateService(
      client: MockClient((http.Request request) async {
        if (request.url.path.endsWith('/releases')) {
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'tag_name': latestTag,
                'html_url': 'https://example.invalid/$latestTag',
                'body': 'notes',
                'prerelease': false,
                'draft': false,
              },
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      }),
      // The app's own version is deliberately newer than the backend's, to
      // prove the comparison uses the backend version and not this.
      packageInfoLoader: () async => PackageInfo(
        appName: 'Neuro Toolkit',
        packageName: 'neuro_toolkit',
        version: '9.9.9',
        buildNumber: '1',
      ),
    );

    test('offers the release when the backend is behind', () async {
      final update = await serviceReturning(
        'v1.2.0',
      ).checkForBackendUpdate('1.1.0');

      expect(update, isNotNull);
      expect(update!.version, '1.2.0');
    });

    test('offers nothing when the backend is already current', () async {
      expect(
        await serviceReturning('v1.2.0').checkForBackendUpdate('1.2.0'),
        isNull,
      );
    });

    test('never offers an update against a source build', () async {
      // "dev" is what an unstamped image reports; there is no release to
      // compare it with, so offering an update would be meaningless.
      expect(
        await serviceReturning('v1.2.0').checkForBackendUpdate('dev'),
        isNull,
      );
      expect(
        await serviceReturning('v1.2.0').checkForBackendUpdate('  '),
        isNull,
      );
    });

    test('offers nothing when GitHub is unreachable', () async {
      final service = UpdateService(
        client: MockClient((http.Request request) async {
          throw http.ClientException('offline');
        }),
        packageInfoLoader: () async => PackageInfo(
          appName: 'Neuro Toolkit',
          packageName: 'neuro_toolkit',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      expect(await service.checkForBackendUpdate('1.1.0'), isNull);
    });
  });
}
