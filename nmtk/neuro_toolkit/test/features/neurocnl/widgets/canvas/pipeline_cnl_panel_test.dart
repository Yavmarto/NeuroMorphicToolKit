import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_cnl_panel.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

ProviderContainer _makeContainer(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = ApiClient(
    baseUrl: 'http://test/api',
    httpClient: MockClient(handler),
  );
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

http.Response _jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 480, height: 600, child: PipelineCnlPanel()),
      ),
    ),
  );
}

void main() {
  testWidgets('renders CNL text from the provider', (tester) async {
    final container = _makeContainer((request) async {
      return _jsonResponse({
        'cnl_text': 'Train the network for 50 epochs.',
        'diagnostics': <String>[],
      });
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pumpAndSettle();

    expect(find.text('Train the network for 50 epochs.'), findsOneWidget);
  });

  testWidgets('Apply button is disabled until the text is edited', (
    tester,
  ) async {
    final container = _makeContainer((request) async {
      return _jsonResponse({
        'cnl_text': 'Train the network for 50 epochs.',
        'diagnostics': <String>[],
      });
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pumpAndSettle();

    final applyButton = tester.widget<ZetaButton>(
      find.byKey(const Key('pipeline-cnl-apply-button')),
    );
    expect(applyButton.onPressed, isNull);
  });

  testWidgets('shows an inline error on a fail-closed parse error', (
    tester,
  ) async {
    final container = _makeContainer((request) async {
      if (request.url.path == '/api/notebook/generate-pipeline-cnl') {
        return _jsonResponse({
          'cnl_text': 'Train the network for 50 epochs.',
          'diagnostics': <String>[],
        });
      }
      return _jsonResponse({'detail': 'unknown_optimizer_phrase'}, 422);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('pipeline-cnl-text-field')),
      'Train the network for 5 epochs with foo optimizer.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('pipeline-cnl-apply-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pipeline-cnl-apply-error')), findsOneWidget);
  });
}
