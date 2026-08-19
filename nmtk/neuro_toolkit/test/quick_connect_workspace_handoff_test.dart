import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/src/features/launcher_bootstrap/presentation/launcher_bootstrap_notifier.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDeploymentService implements DeploymentService {
  @override
  Future<SystemHealthReport> diagnoseTarget(String targetId) {
    throw UnimplementedError();
  }

  @override
  Future<SystemHealthReport> repairTarget(String targetId) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> reinstallTarget(
    String targetId, {
    bool factoryReset = false,
  }) {
    throw UnimplementedError();
  }

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
  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request,
  ) {
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

  @override
  Future<void> forgetHostKey({required String host, required int sshPort}) {
    throw UnimplementedError();
  }
}

class _NoUpdateService extends UpdateService {
  @override
  Future<LauncherUpdate?> checkForLauncherUpdate() async => null;
}

class _InitiallyReadyBootstrapNotifier extends LauncherBootstrapNotifier {
  _InitiallyReadyBootstrapNotifier(this.controlApi);

  final ControlApiService controlApi;

  @override
  Future<LauncherBootstrapData> build() async {
    final settings = await controlApi.fetchSettings();
    return LauncherBootstrapData.ready(
      bootstrapState: LauncherBootstrapState.ready(controlApi.baseUri),
      controlApiService: controlApi,
      launcherSettings: settings,
    );
  }
}

class _StaticConnectionNotifier extends ServerConnectionNotifier {
  @override
  ServerConnectionState build() {
    final baseUri = ref.watch(selectedControlApiServiceProvider)?.baseUri;
    if (baseUri == null) {
      return const ServerConnectionState.disconnected();
    }
    return ServerConnectionState(
      phase: ServerConnectionPhase.connected,
      baseUri: baseUri,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'quick connect dismisses setup and shows the selected launcher workspace',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requestedPaths = <String>[];
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
                    'host': '192.168.2.90',
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
            serverConnectionProvider.overrideWith(
              _StaticConnectionNotifier.new,
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackendSetupScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '192.168.2.90');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The launcher initializes the workspace directly after setup without
      // an outer route transition.
      expect(find.byType(BackendSetupScreen), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(NeuroToolkitApp), findsOneWidget);

      // Dismiss the setup and verify that workspace initialization (which runs
      // in the background) made the expected API calls.
      await tester.pump(const Duration(seconds: 2));
      expect(requestedPaths, contains('/api/launcher/modules'));
      expect(requestedPaths, contains('/api/launcher/workspace'));
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
                    'host': '192.168.2.90',
                    'sshPort': 22,
                    'controlPort': 8091,
                    'runtimeApiUrl': 'http://192.168.2.90:8002',
                    'controlApiUrl': 'http://192.168.2.90:8091',
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
            serverConnectionProvider.overrideWith(
              _StaticConnectionNotifier.new,
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackendSetupScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '192.168.2.90');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pumpAndSettle();

      expect(probedBaseUri, Uri.parse('http://192.168.2.90:8090'));
      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(find.text('No Modules Available'), findsOneWidget);
      expect(requestedPaths, contains('/api/launcher/modules'));
      expect(requestedPaths, contains('/api/launcher/workspace'));

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('launcher_control_api_base_url'),
        'http://192.168.2.90:8090',
      );
      expect(preferences.getString('suite_api_base_url'), isNull);
    },
  );

  testWidgets(
    'change server replaces the active launcher and refreshes the workspace',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'launcher_control_api_base_url': 'http://192.168.2.90:8090',
      });
      final requestedAuthorities = <String>[];
      final requestedPaths = <String>[];
      final staleServerModules = Completer<http.Response>();
      var oldServerModuleRequests = 0;
      final client = MockClient((request) async {
        requestedAuthorities.add(request.url.authority);
        requestedPaths.add('${request.url.host}${request.url.path}');
        switch (request.url.path) {
          case '/health':
            return http.Response(
              jsonEncode(<String, String>{'status': 'ok'}),
              200,
            );
          case '/api/launcher/settings':
            return http.Response(
              jsonEncode(<String, dynamic>{
                'logLevel': 'info',
                'mujocoAvailable': false,
                'pythonAvailable': true,
                'backendDeploymentReady': true,
                'pynqBoards': <dynamic>[],
                'akidaHosts': <dynamic>[],
              }),
              200,
            );
          case '/api/launcher/modules':
            if (request.url.host == '192.168.2.90') {
              oldServerModuleRequests++;
              if (oldServerModuleRequests > 1) {
                return staleServerModules.future;
              }
            }
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
            launcherBootstrapProvider.overrideWith(
              () => _InitiallyReadyBootstrapNotifier(
                ControlApiService(
                  baseUri: Uri.parse('http://192.168.2.90:8090'),
                  client: client,
                  analyticsService: AnalyticsService(),
                ),
              ),
            ),
            serverConnectionProvider.overrideWith(
              _StaticConnectionNotifier.new,
            ),
          ],
          child: const NeuroToolkitApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byKey(const ValueKey<String>('inline-server-connection-icon')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(oldServerModuleRequests, 2);

      tester
          .widget<InkWell>(
            find.byKey(
              const ValueKey<String>('inline-server-connection-icon'),
            ),
          )
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField).first, '192.168.2.34');
      await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const Key('backend-setup-quick-connect-error')),
        findsNothing,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(
        requestedAuthorities,
        containsAll(<String>['192.168.2.90:8090', '192.168.2.34:8090']),
      );
      expect(
        requestedPaths,
        contains('192.168.2.34/api/launcher/modules'),
      );
      expect(
        requestedPaths,
        contains('192.168.2.34/api/launcher/workspace'),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('launcher_control_api_base_url'),
        'http://192.168.2.34:8090',
      );

      staleServerModules.complete(
        http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'old-only',
              'name': 'Old server module',
              'description': 'Must never replace the new server state',
              'installPath': 'old/',
              'port': 9000,
              'hasFrontend': true,
              'status': 4,
            },
          ]),
          200,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Old server module'), findsNothing);

      // Dispose the provider scope so its periodic liveness timer is canceled
      // before the widget-test binding verifies that no timers leaked.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'verified quick connect enters workspace when saving the target fails',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requestedPaths = <String>[];
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
            serverConnectionProvider.overrideWith(
              _StaticConnectionNotifier.new,
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
            if (baseUri.host == '192.168.2.90') {
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
          .connectToLauncher('192.168.2.90');

      expect(message, contains('could not be reached'));
      final activeSelection = container.read(launcherBootstrapProvider).value;
      expect(activeSelection?.isReady, isTrue);
      expect(
        activeSelection?.controlApiService?.baseUri,
        Uri.parse('http://10.0.0.8:8090'),
      );
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
        .connectToLauncher('192.168.2.90');

    expect(message, contains('not ready'));
    expect(container.read(launcherBootstrapProvider).value?.isReady, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('launcher_control_api_base_url'), isNull);
  });
}
