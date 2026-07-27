import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/routing/router.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/src/features/launcher_bootstrap/presentation/launcher_bootstrap_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDeploymentService implements DeploymentService {
  @override
  Future<DeploymentSnapshot> load() async => const DeploymentSnapshot();

  @override
  Future<DeploymentPreflightResult> preflight(DeploymentRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> cancelJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> fetchJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob?> retryJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<void> retryJupyter(String targetId) {
    throw UnimplementedError();
  }
}

class _NoUpdateService extends UpdateService {
  @override
  Future<LauncherUpdate?> checkForLauncherUpdate() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'quick connect from setup navigates to the workspace and shows the selected launcher',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requestedPaths = <String>[];
      final router = createGoRouter(initialLocation: '/setup');
      addTearDown(router.dispose);
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/api/launcher/settings':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'backendDeploymentReady': true,
                'pynqBoards': <dynamic>[],
                'akidaHosts': <dynamic>[
                  <String, dynamic>{
                    'id': 'legacy-akida-host',
                    'host': '192.168.2.51',
                    'controlPort': 8091,
                  },
                ],
              }),
              200,
            );
          case '/api/launcher/modules':
            return http.Response(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'neurocnl',
                  'name': 'NeuroStudio',
                  'description': 'CNL compiler and visual SNN design suite',
                  'installPath': 'neurocnl/',
                  'port': 9000,
                  'hasFrontend': true,
                  'status': 4,
                },
              ]),
              200,
            );
          case '/api/launcher/workspace':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'sessions': <dynamic>[],
                'focusedModuleId': null,
              }),
              200,
            );
          case '/api/launcher/workspace/sessions':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'sessions': <dynamic>[
                  <String, dynamic>{
                    'moduleId': 'neurocnl',
                    'surfaceMode': 'native',
                    'readinessState': 'ready',
                    'restoreState': <String, dynamic>{},
                  },
                ],
                'focusedModuleId': 'neurocnl',
              }),
              200,
            );
          default:
            return http.Response('', 404);
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            goRouterProvider.overrideWithValue(router),
            analyticsServiceProvider.overrideWithValue(AnalyticsService()),
            deploymentServiceProvider.overrideWithValue(
              _FakeDeploymentService(),
            ),
            updateServiceProvider.overrideWithValue(_NoUpdateService()),
            launcherBootstrapProbeProvider.overrideWithValue(
              (baseUri) async => LauncherBootstrapState.ready(baseUri),
            ),
            launcherControlApiFactoryProvider.overrideWithValue(
              (baseUri) => ControlApiService(
                baseUri: baseUri,
                client: client,
                analyticsService: AnalyticsService(),
              ),
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackendSetupScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '192.168.2.51');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(find.text('Connected: 192.168.2.51:8090'), findsOneWidget);
      expect(requestedPaths, contains('/api/launcher/modules'));
      expect(requestedPaths, contains('/api/launcher/workspace'));

      await tester.tap(find.text('Connected: 192.168.2.51:8090'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BackendSetupScreen), findsOneWidget);
    },
  );

  testWidgets(
    'verified quick connect hands the same control service to the workspace',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requestedPaths = <String>[];
      Uri? probedBaseUri;

      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/api/launcher/settings':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'logLevel': 'info',
                'mujocoAvailable': false,
                'pythonAvailable': true,
                'backendDeploymentReady': true,
                'selectedBackendDeploymentTarget': null,
                'pynqBoards': <dynamic>[],
                'akidaHosts': <dynamic>[
                  <String, dynamic>{
                    'id': 'legacy-akida-host',
                    'displayName': 'Hp prodesk',
                    'host': '192.168.2.51',
                    'sshPort': 22,
                    'controlPort': 8091,
                    'runtimeApiUrl': 'http://192.168.2.51:8002',
                    'controlApiUrl': 'http://192.168.2.51:8090',
                    'authMode': 'ssh_key',
                    'runtimeMode': 'unknown',
                    'state': 'simulator_only',
                    'hasPassword': false,
                  },
                ],
                'selectedAkidaHostId': 'legacy-akida-host',
              }),
              200,
            );
          case '/api/launcher/modules':
            return http.Response('[]', 200);
          case '/api/launcher/workspace':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'sessions': <dynamic>[],
                'focusedModuleId': null,
              }),
              200,
            );
          default:
            return http.Response('', 404);
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsServiceProvider.overrideWithValue(AnalyticsService()),
            deploymentServiceProvider.overrideWithValue(
              _FakeDeploymentService(),
            ),
            updateServiceProvider.overrideWithValue(_NoUpdateService()),
            launcherBootstrapProbeProvider.overrideWithValue((baseUri) async {
              probedBaseUri = baseUri;
              return LauncherBootstrapState.ready(baseUri);
            }),
            launcherControlApiFactoryProvider.overrideWithValue(
              (baseUri) => ControlApiService(
                baseUri: baseUri,
                client: client,
                analyticsService: AnalyticsService(),
              ),
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackendSetupScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '192.168.2.51');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pumpAndSettle();

      expect(probedBaseUri, Uri.parse('http://192.168.2.51:8090'));
      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(find.text('No Modules Available'), findsOneWidget);
      expect(requestedPaths, contains('/api/launcher/modules'));
      expect(requestedPaths, contains('/api/launcher/workspace'));

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('launcher_control_api_base_url'),
        'http://192.168.2.51:8090',
      );
      expect(preferences.getString('suite_api_base_url'), isNull);
    },
  );

  testWidgets(
    'verified quick connect enters workspace when saving the target fails',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requestedPaths = <String>[];
      final router = createGoRouter(initialLocation: '/setup');
      addTearDown(router.dispose);
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/api/launcher/settings':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'backendDeploymentReady': true,
                'selectedBackendDeploymentTarget': null,
                'pynqBoards': <dynamic>[],
                'akidaHosts': <dynamic>[
                  <String, dynamic>{
                    'id': 'local-akida-auto',
                    'displayName': 'Local Akida',
                    'host': 'neurochip-hw-worker',
                    'port': 8002,
                    'controlPort': 8091,
                    'runtimeApiUrl': 'http://neurochip-hw-worker:8002',
                    'controlApiUrl': 'http://neurochip-hw-worker:8091',
                    'authMode': 'password',
                    'state': 'unknown',
                  },
                ],
                'selectedAkidaHostId': 'local-akida-auto',
              }),
              200,
            );
          case '/api/launcher/modules':
            return http.Response('[]', 200);
          case '/api/launcher/workspace':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'sessions': <dynamic>[],
                'focusedModuleId': null,
              }),
              200,
            );
          default:
            return http.Response('', 404);
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            goRouterProvider.overrideWithValue(router),
            analyticsServiceProvider.overrideWithValue(AnalyticsService()),
            deploymentServiceProvider.overrideWithValue(
              _FakeDeploymentService(),
            ),
            updateServiceProvider.overrideWithValue(_NoUpdateService()),
            launcherBootstrapProbeProvider.overrideWithValue(
              (baseUri) async => LauncherBootstrapState.ready(baseUri),
            ),
            launcherControlApiFactoryProvider.overrideWithValue(
              (baseUri) => ControlApiService(
                baseUri: baseUri,
                client: client,
                analyticsService: AnalyticsService(),
              ),
            ),
            launcherSelectionSaverProvider.overrideWithValue(
              (_, __) async => throw StateError('preferences unavailable'),
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '192.168.2.34');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pumpAndSettle();

      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(find.text('No Modules Available'), findsOneWidget);
      expect(requestedPaths, contains('/api/launcher/modules'));
      expect(requestedPaths, contains('/api/launcher/workspace'));
    },
  );

  test(
    'failed candidate does not overwrite the last verified server',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'launcher_control_api_base_url': 'http://10.0.0.8:8090',
        'suite_api_base_url': 'http://10.0.0.8:9000',
      });
      final settingsClient = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'backendDeploymentReady': true,
            'pynqBoards': <dynamic>[],
            'akidaHosts': <dynamic>[],
          }),
          200,
        );
      });
      final container = ProviderContainer(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          launcherBootstrapProbeProvider.overrideWithValue((baseUri) async {
            if (baseUri.host == '192.168.2.51') {
              return LauncherBootstrapState.preflightFailed(
                baseUri,
                'The launcher host could not be reached.',
              );
            }
            return LauncherBootstrapState.ready(baseUri);
          }),
          launcherControlApiFactoryProvider.overrideWithValue(
            (baseUri) => ControlApiService(
              baseUri: baseUri,
              client: settingsClient,
              analyticsService: AnalyticsService(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final initial = await container.read(launcherBootstrapProvider.future);
      expect(initial.isReady, isTrue);

      final message = await container
          .read(launcherBootstrapProvider.notifier)
          .connectToLauncher('192.168.2.51');

      expect(message, contains('could not be reached'));
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('launcher_control_api_base_url'),
        'http://10.0.0.8:8090',
      );
      expect(
        preferences.getString('suite_api_base_url'),
        'http://10.0.0.8:9000',
      );
    },
  );

  test('restart probes the previously verified launcher URL', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'launcher_control_api_base_url': 'https://launcher.example:8443',
    });
    Uri? probedBaseUri;
    final settingsClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'backendDeploymentReady': true,
          'pynqBoards': <dynamic>[],
          'akidaHosts': <dynamic>[],
        }),
        200,
      );
    });
    final container = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(AnalyticsService()),
        launcherBootstrapProbeProvider.overrideWithValue((baseUri) async {
          probedBaseUri = baseUri;
          return LauncherBootstrapState.ready(baseUri);
        }),
        launcherControlApiFactoryProvider.overrideWithValue(
          (baseUri) => ControlApiService(
            baseUri: baseUri,
            client: settingsClient,
            analyticsService: AnalyticsService(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final result = await container.read(launcherBootstrapProvider.future);

    expect(result.isReady, isTrue);
    expect(probedBaseUri, Uri.parse('https://launcher.example:8443'));
  });

  test('reachable launcher with an unready backend remains on setup', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settingsClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'backendDeploymentReady': false,
          'pynqBoards': <dynamic>[],
          'akidaHosts': <dynamic>[],
        }),
        200,
      );
    });
    final container = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(AnalyticsService()),
        launcherBootstrapProbeProvider.overrideWithValue(
          (baseUri) async => LauncherBootstrapState.ready(baseUri),
        ),
        launcherControlApiFactoryProvider.overrideWithValue(
          (baseUri) => ControlApiService(
            baseUri: baseUri,
            client: settingsClient,
            analyticsService: AnalyticsService(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    await container.read(launcherBootstrapProvider.future);
    final message = await container
        .read(launcherBootstrapProvider.notifier)
        .connectToLauncher('192.168.2.51');

    expect(message, contains('not ready'));
    expect(container.read(launcherBootstrapProvider).value?.isReady, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('launcher_control_api_base_url'), isNull);
  });
}
