import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_tab_file_view_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_top_bar/studio_utility_pill.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('StudioUtilityPill wires the Save to Neurohub action', (
    tester,
  ) async {
    var shared = 0;
    var saved = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: ZetaProvider(
          initialContrast: ZetaContrast.aa,
          initialThemeMode: ThemeMode.dark,
          builder: (context, light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            home: Scaffold(
              body: Center(
                child: StudioUtilityPill(
                  files: const <WorkspaceTabFileViewData>[
                    WorkspaceTabFileViewData(
                      id: 'model',
                      name: 'model.cnl',
                      dirty: false,
                    ),
                  ],
                  activeFileId: 'model',
                  workspaceName: 'Demo workspace',
                  onSelected: (_) {},
                  onClosed: (_) {},
                  onSaveActiveFile: () => saved++,
                  onShareToNeurohub: () => shared++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Save workspace'), findsOneWidget);
    expect(find.byTooltip('Save to Neurohub'), findsOneWidget);

    await tester.tap(find.byTooltip('Save to Neurohub'));
    await tester.pump();
    expect(shared, 1);
    expect(saved, 0);

    await tester.tap(find.byTooltip('Save workspace'));
    await tester.pump();
    expect(saved, 1);
  });
}
