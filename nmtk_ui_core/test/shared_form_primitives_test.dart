import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('content dialog renders rich content and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ZetaProvider(
        initialContrast: ZetaContrast.aa,
        initialThemeMode: ThemeMode.dark,
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: Builder(
            builder: (context) => ZetaButton(
              label: 'Open',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => NmtkContentDialog(
                  title: 'Import requirements',
                  content: const Text('Structured content'),
                  actions: [
                    ZetaButton.text(
                      label: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Import requirements'), findsOneWidget);
    expect(find.text('Structured content'), findsOneWidget);
  });

  testWidgets('code text area edits with the registered monospace font', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ZetaProvider(
        initialContrast: ZetaContrast.aa,
        initialThemeMode: ThemeMode.dark,
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: Scaffold(
            body: NmtkCodeTextArea(
              controller: controller,
              label: 'requirements.txt',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.enterText(find.byType(TextField), 'numpy==2.0');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(controller.text, 'numpy==2.0');
    expect(field.style?.fontFamily, endsWith(NmtkFontFamilies.monospace));
  });

  testWidgets('interactive status badge supports pointer and keyboard', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      ZetaProvider(
        initialContrast: ZetaContrast.aa,
        initialThemeMode: ThemeMode.dark,
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: Scaffold(
            body: NmtkStatusBadge(
              label: 'Ready',
              tone: NmtkTone.success,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text('Ready'));
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 2);
  });
}
