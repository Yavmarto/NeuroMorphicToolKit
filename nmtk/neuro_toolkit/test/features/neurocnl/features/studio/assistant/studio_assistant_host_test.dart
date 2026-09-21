import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_host.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_panel.dart';
import 'package:neuro_toolkit/ui_core/contrast_utils.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

Widget _host({
  required ThemeMode mode,
  required Widget child,
  Size viewport = const Size(390, 844),
}) {
  return ProviderScope(
    child: _themedHost(mode: mode, viewport: viewport, child: child),
  );
}

Widget _themedHost({
  required ThemeMode mode,
  required Widget child,
  Size viewport = const Size(390, 844),
}) {
  return ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: mode,
    builder: (context, light, dark, effective) => MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: effective,
      home: MediaQuery(
        data: MediaQueryData(size: viewport),
        child: child,
      ),
    ),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'mobile has no floating launcher — the assistant opens from the top '
    'bar via StudioAssistantScope instead',
    (tester) async {
      const viewport = Size(390, 844);
      _useViewport(tester, viewport);
      await tester.pumpWidget(
        _host(
          mode: ThemeMode.light,
          viewport: viewport,
          child: StudioAssistantHost(
            isMobile: true,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: StudioAssistantScope.maybeOf(context),
                child: const Text('open from app bar'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.text('open from app bar'));
      await tester.pumpAndSettle();

      expect(find.byType(StudioAssistantPanel), findsOneWidget);
    },
  );

  testWidgets('desktop launcher stays extended in the bottom corner', (
    tester,
  ) async {
    _useViewport(tester, const Size(1200, 900));
    await tester.pumpWidget(
      _host(
        mode: ThemeMode.light,
        viewport: const Size(1200, 900),
        child: const StudioAssistantHost(
          isMobile: false,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Assistant'), findsOneWidget);

    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byIcon(ZetaIcons.chat),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.right, 16);
    expect(positioned.bottom, 16);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '$mode: desktop assistant FAB icon clears 3:1 against its background',
      (tester) async {
        _useViewport(tester, const Size(1200, 900));
        await tester.pumpWidget(
          _host(
            mode: mode,
            viewport: const Size(1200, 900),
            child: const StudioAssistantHost(
              isMobile: false,
              child: SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        final fabFinder = find.byType(FloatingActionButton);
        final fab = tester.widget<FloatingActionButton>(fabFinder);
        final icon = tester.widget<Icon>(find.byIcon(ZetaIcons.chat));
        final bg =
            fab.backgroundColor ??
            Theme.of(tester.element(fabFinder)).colorScheme.primary;
        expect(nmtkContrastRatio(icon.color!, bg), greaterThanOrEqualTo(3.0));
      },
    );
  }
}
