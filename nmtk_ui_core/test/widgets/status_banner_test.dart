// Unit tests for NmtkStatusBanner (introduced by zeta-card-reduction Task 2).
//
// NmtkStatusBanner must:
//   1. Render exactly one ZetaInPageBanner per banner.
//   2. Map every NmtkTone to the correct ZetaWidgetStatus.
//   3. Never render a NmtkSurfaceCard ancestor in its subtree (it's a banner,
//      not a card).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

Future<void> _pumpBanner(
  WidgetTester tester, {
  required NmtkTone tone,
  Widget? content,
  bool canClose = false,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    ZetaProvider(
      initialContrast: ZetaContrast.aa,
      initialThemeMode: ThemeMode.dark,
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: Scaffold(
          body: NmtkStatusBanner(
            title: 'banner-title',
            tone: tone,
            content: content,
            canClose: canClose,
            onClose: onClose,
          ),
        ),
      ),
    ),
  );
  // Two frames let ZetaInPageBanner mount its content; the close-icon ripple
  // keeps a ticker open so pumpAndSettle would time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('nmtkToneToZetaWidgetStatus', () {
    test('maps every tone deterministically', () {
      expect(
        nmtkToneToZetaWidgetStatus(NmtkTone.neutral),
        ZetaWidgetStatus.info,
      );
      expect(nmtkToneToZetaWidgetStatus(NmtkTone.info), ZetaWidgetStatus.info);
      expect(
        nmtkToneToZetaWidgetStatus(NmtkTone.success),
        ZetaWidgetStatus.positive,
      );
      expect(
        nmtkToneToZetaWidgetStatus(NmtkTone.warning),
        ZetaWidgetStatus.warning,
      );
      expect(
        nmtkToneToZetaWidgetStatus(NmtkTone.danger),
        ZetaWidgetStatus.negative,
      );
    });
  });

  group('NmtkStatusBanner', () {
    testWidgets('renders exactly one ZetaInPageBanner per banner', (
      tester,
    ) async {
      await _pumpBanner(tester, tone: NmtkTone.success);
      expect(find.byType(ZetaInPageBanner), findsOneWidget);
    });

    testWidgets('forwards the title to ZetaInPageBanner', (tester) async {
      await _pumpBanner(tester, tone: NmtkTone.success);
      expect(find.text('banner-title'), findsOneWidget);
    });

    testWidgets('renders no NmtkSurfaceCard ancestor', (tester) async {
      await _pumpBanner(
        tester,
        tone: NmtkTone.success,
        content: const Text('payload'),
      );
      expect(find.byType(NmtkSurfaceCard), findsNothing);
    });

    testWidgets('renders provided content', (tester) async {
      await _pumpBanner(
        tester,
        tone: NmtkTone.warning,
        content: const Text('content-payload'),
      );
      expect(find.text('content-payload'), findsOneWidget);
    });

    testWidgets('forwards status to ZetaInPageBanner per tone', (tester) async {
      for (final pair in const <(NmtkTone, ZetaWidgetStatus)>[
        (NmtkTone.neutral, ZetaWidgetStatus.info),
        (NmtkTone.info, ZetaWidgetStatus.info),
        (NmtkTone.success, ZetaWidgetStatus.positive),
        (NmtkTone.warning, ZetaWidgetStatus.warning),
        (NmtkTone.danger, ZetaWidgetStatus.negative),
      ]) {
        await _pumpBanner(tester, tone: pair.$1);
        final banner = tester.widget<ZetaInPageBanner>(
          find.byType(ZetaInPageBanner),
        );
        expect(
          banner.status,
          pair.$2,
          reason: 'NmtkTone.${pair.$1.name} must map to ${pair.$2}',
        );
      }
    });

    testWidgets('canClose: false suppresses the close affordance', (
      tester,
    ) async {
      await _pumpBanner(tester, tone: NmtkTone.info);
      final banner = tester.widget<ZetaInPageBanner>(
        find.byType(ZetaInPageBanner),
      );
      expect(banner.onClose, isNull);
    });

    testWidgets('canClose: true wires onClose through to ZetaInPageBanner', (
      tester,
    ) async {
      var closed = false;
      await _pumpBanner(
        tester,
        tone: NmtkTone.info,
        canClose: true,
        onClose: () => closed = true,
      );
      final banner = tester.widget<ZetaInPageBanner>(
        find.byType(ZetaInPageBanner),
      );
      expect(banner.onClose, isNotNull);
      banner.onClose?.call();
      expect(closed, isTrue);
    });
  });
}
