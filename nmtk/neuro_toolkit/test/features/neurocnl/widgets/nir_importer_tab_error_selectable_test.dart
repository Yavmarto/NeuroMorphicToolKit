// Widget Test — NirImporterTab error view avoids selection auto-scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/nir_importer_tab.dart';

const _errorMessage = 'Failed to parse NIR file: unexpected EOF at byte 4096.';

ProviderContainer _makeErrorContainer() {
  final container = ProviderContainer();
  container.read(nirImportProvider.notifier).state = const NirImportState.error(
    source: NirSource.file,
    error: _errorMessage,
  );
  return container;
}

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, height: 700, child: NirImporterTab()),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('error view renders the message without a SelectionArea', (
    WidgetTester tester,
  ) async {
    final container = _makeErrorContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pumpAndSettle();

    expect(find.text(_errorMessage), findsOneWidget);
    expect(find.text('Failed to parse NIR file'), findsOneWidget);

    expect(find.byType(SelectionArea), findsNothing);
  });
}
