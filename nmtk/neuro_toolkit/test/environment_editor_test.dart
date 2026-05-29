import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/environment_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/environment_editor.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';

const _envsJson = {
  'environments': [
    {
      'slug': 'neurocnl',
      'displayName': 'Python (NeuroStudio)',
      'kernelName': 'neurocnl',
      'immutable': true,
      'pythonVersion': '3.11.0',
      'packageCount': 42,
      'basedOn': null,
      'createdAt': null,
    },
    {
      'slug': 'experiments',
      'displayName': 'Experiments',
      'kernelName': 'experiments',
      'immutable': false,
      'pythonVersion': '3.11.0',
      'packageCount': 43,
      'basedOn': 'neurocnl',
      'createdAt': '2026-05-29T00:00:00Z',
    },
  ],
};

EnvironmentProvider _providerWith(MockClient client) {
  final service = EnvironmentApiService(
    controlApi: ControlApiService(baseUri: Uri.parse('http://127.0.0.1:8090')),
    client: client,
  );
  return EnvironmentProvider(service);
}

Widget _shell(EnvironmentProvider provider) {
  return ProviderScope(
    overrides: [
      environmentStateProvider.overrideWith((ref) => provider),
    ],
    // Provide Zeta synchronously: passing both initialThemeMode + initialContrast
    // skips ZetaProvider's async theme-preferences FutureBuilder (which would
    // otherwise render a spinner forever under the test's fake-async clock).
    child: ZetaProvider(
      initialThemeMode: ThemeMode.light,
      initialContrast: ZetaContrast.aa,
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: const EnvironmentEditorScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('lists base + clone, flags the immutable base', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/jupyter/environments') {
        return http.Response(jsonEncode(_envsJson), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });

    final provider = _providerWith(client);
    // Pre-load via runAsync so the data is present before we pump frames; the
    // screen's own postFrame refresh would otherwise resolve in the fake-async
    // zone that tester.pump() cannot drive for the MockClient stream.
    await tester.runAsync(() => provider.refresh());

    await tester.pumpWidget(_shell(provider));
    await tester.pump();

    expect(find.text('Python (NeuroStudio)'), findsOneWidget);
    expect(find.text('Experiments'), findsOneWidget);
    expect(find.text('Immutable'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    // The immutable base must not offer a Delete action; the clone must.
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('shows an error state when the backend is unreachable',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'error': 'Jupyter Server not reachable'}),
        503,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = _providerWith(client);
    await tester.runAsync(() => provider.refresh());

    await tester.pumpWidget(_shell(provider));
    await tester.pump();

    expect(find.text('Environments unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
