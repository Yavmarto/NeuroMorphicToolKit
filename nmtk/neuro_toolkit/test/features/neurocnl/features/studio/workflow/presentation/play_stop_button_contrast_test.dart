import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/presentation/play_stop_button.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/ui_core/contrast_utils.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show NmtkShellTokens;

/// CEL-455 audit finding: the run/execute step's play/stop control (used
/// inside `RunActionBar`, the mobile bottom bar for the run step) painted
/// its "running" spinner and stop icon with `NmtkShellTokens.healthyColor`
/// (the success/green semantic) instead of `runningColor` (the in-progress
/// semantic). A job that is still running has not succeeded yet, so the
/// wrong token was load-bearing, not cosmetic.
///
/// `RunActionBar` renders this control on a fixed dark-navy bar
/// (`AppTheme.surface`, `#0F172A`) that does not change between light and
/// dark theme — the same "fixed bar, theme-independent ink" shape as the
/// CEL-92 canvas toolbar regression — so contrast must be measured against
/// that literal color in both themes, not assumed from the token being
/// "theme-aware".
Widget _host({required ThemeMode mode, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
    darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    themeMode: mode,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: AppTheme.surface,
      body: Center(
        child: Builder(
          builder: (context) => Container(color: AppTheme.surface, child: child),
        ),
      ),
    ),
  );
}

Widget _playStop({required bool isRunning}) {
  return Builder(
    builder: (context) => PlayStopButton(
      enabled: true,
      isRunning: isRunning,
      onPlay: () {},
      onStop: () {},
      l10n: AppLocalizations.of(context)!,
    ),
  );
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name} theme: running stop-icon uses runningColor, not healthyColor',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: mode, child: _playStop(isRunning: true)),
        );
        await tester.pump();
        // Let the pulse animation advance so alpha != 0 before we sample color.
        await tester.pump(const Duration(milliseconds: 450));

        final context = tester.element(find.byKey(const Key('stop-icon')));
        final runningColor = NmtkShellTokens.of(context).runningColor;
        final healthyColor = NmtkShellTokens.of(context).healthyColor;

        final icon = tester.widget<Icon>(find.byKey(const Key('stop-icon')));
        expect(
          icon.color,
          runningColor,
          reason:
              'A running job must use the "running" semantic color, not '
              '"healthy"/success — the job has not completed yet.',
        );
        expect(icon.color, isNot(healthyColor));
      },
    );

    testWidgets(
      '${mode.name} theme: running stop-icon clears 3:1 on the run-bar surface',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: mode, child: _playStop(isRunning: true)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));

        final icon = tester.widget<Icon>(find.byKey(const Key('stop-icon')));
        final ratio = nmtkContrastRatio(icon.color!, AppTheme.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              'stop-icon vs run-bar surface (${mode.name} theme) measured '
              '${ratio.toStringAsFixed(2)}:1, must clear the WCAG 1.4.11 '
              '3:1 non-text floor',
        );
      },
    );
  }
}
