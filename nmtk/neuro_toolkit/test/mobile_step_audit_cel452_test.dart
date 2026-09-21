// CEL-452 mobile audit for the deployment setup step flow:
//
//   lib/features/neurocnl/features/studio/deployment/deploy/akida_setup_pane
//   lib/features/neurocnl/features/studio/deployment/deploy/pynq_setup_pane
//   lib/features/neurocnl/features/studio/deployment/hardware_target/
//       add_hardware_target_form
//
// Pumps the setup panes at the two required narrow widths (375x667 iPhone
// SE, 390x844 iPhone 14) and fails on a RenderFlex overflow — these panes are
// always hosted inside a scrollable dialog body in production, so the host
// here mirrors that (bounded width, scrollable height) rather than testing an
// unrealistic unbounded Column.
//
// Also regression-tests the CEL-452 fix to AddHardwareTargetForm: the form's
// Cancel button used to be disabled while a save was in flight, which left
// the "Add/Edit target" dialog with no working back/cancel affordance during
// its loading state (the dialog itself has no close button while the form is
// showing — see hardware_target_dialog.dart). Cancel must stay enabled in
// every state.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_advanced_scaffold_pane/akida_advanced_scaffold_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_setup_pane/akida_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_setup_pane/pynq_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/add_hardware_target_form/add_hardware_target_form.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);
const List<Size> _phoneSizes = <Size>[_iphoneSe, _iphone14];

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<List<String>> _captureOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed by')) {
      overflows.add(message);
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return overflows;
}

void _expectNoOverflow(List<String> overflows) {
  expect(overflows, isEmpty, reason: overflows.join('\n'));
}

class _StubSpecTextController extends SpecTextController {
  @override
  String build() => '';
}

/// Mirrors the proven CEL-429/430 harness: `ZetaProvider` direct (not
/// `NmtkZetaTheme.wrap`, whose async custom-theme load never settles in tests).
Widget _app({required Widget home}) {
  return ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: ThemeMode.light,
    builder: (context, light, dark, mode) => ProviderScope(
      overrides: [
        specTextProvider.overrideWith(_StubSpecTextController.new),
        serverConfigProvider.overrideWithValue(
          ServerConfigState(serverUrl: 'http://127.0.0.1:9000'),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: home,
      ),
    ),
  );
}

/// Mirrors how these panes are actually hosted in production: a scrollable
/// dialog body of bounded width (`showHardwareTargetDialog` /
/// `deploy_targets_overview/support.dart`), not a bare unbounded Column.
Widget _scrollableHost(Widget child) {
  return _app(
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

/// Mirrors `HardwareTargetDialog`'s content area: a bounded-height surface
/// (an `AlertDialog`'s content box) that the form scrolls internally.
Widget _dialogHost(Widget child) {
  return _app(
    home: Scaffold(
      body: Center(child: SizedBox(width: 560, height: 640, child: child)),
    ),
  );
}

void main() {
  group('overflow — deployment setup panes', () {
    for (final size in _phoneSizes) {
      final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('AkidaSetupPane (no host paired) fits $sizeLabel', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _scrollableHost(
              AkidaSetupPane(
                provider: const StudioAkidaDeployState(),
                selectedHost: null,
                workspaceName: 'cel452-demo-workspace',
                onCreateDemo: () {},
                isCompact: true,
                onManageHardwareTarget: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
        });
        expect(find.text('Deployment setup'), findsOneWidget);
        expect(find.byKey(const Key('akida-pair-host')), findsOneWidget);
        _expectNoOverflow(overflows);
      });

      testWidgets('AkidaAdvancedScaffoldPane fits $sizeLabel', (tester) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _scrollableHost(
              const AkidaAdvancedScaffoldPane(
                provider: StudioAkidaDeployState(),
                selectedHost: null,
              ),
            ),
          );
          await tester.pumpAndSettle();
        });
        expect(find.textContaining('placeholder weights'), findsOneWidget);
        expect(find.byKey(const Key('akida-version-akida1')), findsOneWidget);
        _expectNoOverflow(overflows);
      });

      testWidgets('PynqSetupPane (no board paired) fits $sizeLabel', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _scrollableHost(
              PynqSetupPane(
                provider: const StudioPynqDeployState(),
                selectedBoard: null,
                onManageHardwareTarget: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
        });
        expect(find.text('Board setup'), findsOneWidget);
        expect(find.byKey(const Key('pynq-pair-board')), findsOneWidget);
        _expectNoOverflow(overflows);
      });

      testWidgets('AddHardwareTargetForm (add pynq target) fits $sizeLabel', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _dialogHost(
              AddHardwareTargetForm(
                targetType: 'pynq',
                initialEntry: null,
                errorMessage: null,
                isSaving: false,
                onCancel: () {},
                onSave: (_) async {},
              ),
            ),
          );
          await tester.pumpAndSettle();
        });
        expect(find.text('Cancel'), findsOneWidget);
        _expectNoOverflow(overflows);
      });
    }
  });

  group('back/cancel affordance — AddHardwareTargetForm', () {
    testWidgets('Cancel is enabled while the form is idle', (tester) async {
      _useViewport(tester, _iphoneSe);
      await tester.pumpWidget(
        _dialogHost(
          AddHardwareTargetForm(
            targetType: 'pynq',
            initialEntry: null,
            errorMessage: null,
            isSaving: false,
            onCancel: () {},
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cancelButton = tester.widget<ZetaButton>(
        find.widgetWithText(ZetaButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNotNull);
    });

    testWidgets('Cancel stays a working affordance while a save is in flight '
        '(regression: this used to be disabled, stranding the dialog with no '
        'back/cancel affordance in its loading state)', (tester) async {
      _useViewport(tester, _iphoneSe);
      var cancelled = false;
      await tester.pumpWidget(
        _dialogHost(
          AddHardwareTargetForm(
            targetType: 'pynq',
            initialEntry: null,
            errorMessage: null,
            isSaving: true,
            onCancel: () => cancelled = true,
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cancelFinder = find.widgetWithText(ZetaButton, 'Cancel');
      expect(cancelFinder, findsOneWidget);
      final cancelButton = tester.widget<ZetaButton>(cancelFinder);
      expect(
        cancelButton.onPressed,
        isNotNull,
        reason:
            'Cancel must remain tappable in the loading state — it is the '
            'only back/cancel affordance the Add/Edit target dialog has '
            'while the form is showing.',
      );

      await tester.tap(cancelFinder);
      expect(cancelled, isTrue);

      // The Save actions, in contrast, are correctly disabled mid-save.
      final saveButton = tester.widget<ZetaButton>(
        find.widgetWithText(ZetaButton, 'Saving...'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });
}
