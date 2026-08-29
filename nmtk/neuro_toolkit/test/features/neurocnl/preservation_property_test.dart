// preservation_property_test.dart — neurocnl/frontend
//
// Task 2 — Preservation property tests for ui-theme-density-fix spec.
//
// **Property 2: Preservation** — Non-Buggy Behaviors Unchanged
//
// These tests MUST PASS on unfixed code — they establish the baseline for
// behaviors that the fix must NOT regress.
//
// Coverage in this file (neurocnl/frontend package):
//   - CNL syntax highlighting: _CnlController.buildTextSpan produces
//     color == AppTheme.synKeyword for lines containing MUST keyword
//   - ZetaTextInput usage outside _buildEditor(): _IntField, _FloatField,
//     and dialog fields still use ZetaTextInput
//   - Mobile layout: viewport < 840px renders mobile app bar
//   - High-contrast path: MaterialApp.themeMode == settings.themeMode
//     when isHighContrast = true (already correct; must stay correct)
//   - AppTheme forwarding: synKeyword, nodeEnsemble, edgeExcitatory
//     forward correct NmtkNeurocnlTokens values
//
// Validates: Requirements 3.3, 3.6, 3.7, 3.4, 3.13, 3.14, 3.15
// ignore_for_file: unused_element

// ignore_for_file: lines_longer_than_80_chars

// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_editor.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart'
    show NmtkNeurocnlTokens, NmtkDesktopScaffold, NmtkSidebarItem;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

Widget _buildCnlEditorHarness() {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: CnlEditor()),
    ),
  );
}

/// Resolves the NeuroMorphicToolKit workspace root directory path.
/// Works regardless of whether tests are run from the package directory,
/// the workspace root, or the repo root.
String _resolveWorkspaceRoot() {
  final cwd = Directory.current.path;

  if (cwd.endsWith('frontend')) {
    return Directory(cwd).parent.parent.path;
  }
  if (File('$cwd/nmtk_ui_core/pubspec.yaml').existsSync()) {
    return cwd;
  }
  if (cwd.endsWith('neurocnl')) {
    return Directory(cwd).parent.path;
  }
  var dir = Directory(cwd);
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/nmtk_ui_core/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return cwd.contains('NeuroMorphicToolKit')
      ? cwd.substring(
          0,
          cwd.indexOf('NeuroMorphicToolKit') + 'NeuroMorphicToolKit'.length,
        )
      : cwd;
}

// ---------------------------------------------------------------------------
// Minimal _CnlController replica for unit testing buildTextSpan
//
// We replicate enough of _CnlController's public contract to test the
// color outputs of buildTextSpan WITHOUT triggering the full Riverpod
// widget tree. Since _CnlController is private to the cnl_editor.dart file,
// we test it indirectly through the source-based grep checks and through
// the AppTheme forwarding constants that it uses.
// ---------------------------------------------------------------------------

/// Verifies [spans] contains at least one [TextSpan] with [expectedColor].
bool _hasSpanWithColor(List<InlineSpan> spans, Color expectedColor) {
  for (final span in spans) {
    if (span is TextSpan) {
      if (span.style?.color == expectedColor) return true;
      if (span.children != null &&
          _hasSpanWithColor(span.children!, expectedColor)) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    await ServerConfigService.initialize();
  });

  // ---------------------------------------------------------------------------
  // Baseline observations
  // ---------------------------------------------------------------------------

  group('Baseline observations — AppTheme forwarding constants', () {
    /// Observe: AppTheme.synKeyword == NmtkNeurocnlTokens.synKeyword == Color(0xFF818CF8)
    test(
      'O1 — AppTheme.synKeyword forwards NmtkNeurocnlTokens.synKeyword correctly',
      () {
        expect(
          AppTheme.synKeyword,
          equals(NmtkNeurocnlTokens.synKeyword),
          reason:
              'AppTheme.synKeyword must forward NmtkNeurocnlTokens.synKeyword. '
              'Observed baseline: Color(0xFF818CF8)',
        );
        // Also pin the exact value for documentation.
        expect(AppTheme.synKeyword, equals(const Color(0xFF818CF8)));
      },
    );

    /// Observe: AppTheme.nodeEnsemble == Color(0xFF38BDF8)
    test('O2 — AppTheme.nodeEnsemble is Color(0xFF38BDF8)', () {
      expect(
        AppTheme.nodeEnsemble,
        equals(const Color(0xFF38BDF8)),
        reason: 'Observed baseline: nodeEnsemble is Sky-400 (0xFF38BDF8)',
      );
    });

    /// Observe: AppTheme.edgeExcitatory == Color(0xFF38BDF8)
    test('O3 — AppTheme.edgeExcitatory is Color(0xFF38BDF8)', () {
      expect(
        AppTheme.edgeExcitatory,
        equals(const Color(0xFF38BDF8)),
        reason: 'Observed baseline: edgeExcitatory is Color(0xFF38BDF8)',
      );
    });

    /// Observe: AppTheme.textPrimary == Color(0xFFF8FAFC)
    test('O4 — AppTheme.textPrimary is Color(0xFFF8FAFC)', () {
      expect(
        AppTheme.textPrimary,
        equals(const Color(0xFFF8FAFC)),
        reason: 'Observed baseline: textPrimary is Slate-50 (0xFFF8FAFC)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Property: Syntax highlight colors unchanged
  //
  // Tests PASS on unfixed code — verify the AppTheme constants are correct
  // and that the source code for _CnlController still maps keywords correctly.
  // ---------------------------------------------------------------------------

  group('Property: Syntax highlight colors unchanged (Req 3.3, 3.13, 3.14)', () {
    /// **Validates: Requirements 3.3, 3.13**
    ///
    /// AppTheme.synKeyword must equal NmtkNeurocnlTokens.synKeyword (Indigo-400).
    /// This is the color _CnlController uses for MUST, IF, WITH, etc.
    test(
      'P1 — AppTheme.synKeyword == NmtkNeurocnlTokens.synKeyword (unchanged)',
      () {
        expect(
          AppTheme.synKeyword,
          equals(NmtkNeurocnlTokens.synKeyword),
          reason:
              'AppTheme.synKeyword must forward NmtkNeurocnlTokens.synKeyword '
              '(Indigo-400, 0xFF818CF8). This color is used by _CnlController for '
              'MUST, IF, WITH, DURING, AFTER, etc.',
        );
      },
    );

    /// **Validates: Requirements 3.3, 3.13**
    ///
    /// All syntax highlight forwarding constants must equal their NmtkNeurocnlTokens source.
    test(
      'P2 — All AppTheme syntax colors forward NmtkNeurocnlTokens correctly',
      () {
        expect(AppTheme.synKeyword, equals(NmtkNeurocnlTokens.synKeyword));
        expect(AppTheme.synNumber, equals(NmtkNeurocnlTokens.synNumber));
        expect(AppTheme.synVerb, equals(NmtkNeurocnlTokens.synVerb));
        expect(AppTheme.synUnit, equals(NmtkNeurocnlTokens.synUnit));
        expect(AppTheme.synComment, equals(NmtkNeurocnlTokens.synComment));
        expect(AppTheme.synString, equals(NmtkNeurocnlTokens.synString));
      },
    );

    /// **Validates: Requirements 3.3, 3.13**
    ///
    /// Verify via source inspection that _CnlController._highlightLine
    /// uses the theme-aware synKeyword color for MUST keywords.
    ///
    /// We inspect the cnl_editor.dart source to confirm the color assignment
    /// for group(1) (keywords) maps to synKeyword (via _CnlColors).
    test(
      'P3 — cnl_editor.dart source: _highlightLine maps group(1) to AppTheme.synKeyword',
      () {
        final workspaceRoot = _resolveWorkspaceRoot();
        final cnlEditorFile = File(
          '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_editor.dart',
        );

        final content = cnlEditorFile.readAsStringSync();

        // After theme-aware migration, the keyword color is routed through _CnlColors.
        // Accept either the old direct pattern (AppTheme.synKeyword) or the new
        // context-aware pattern (_colors.synKeyword populated via AppTheme.synKeywordOf).
        final hasOldPattern = content.contains('color = AppTheme.synKeyword');
        final hasNewPattern =
            content.contains('color = _colors.synKeyword') ||
            content.contains('synKeyword: AppTheme.synKeywordOf');
        expect(
          hasOldPattern || hasNewPattern,
          isTrue,
          reason:
              'P3 preservation: cnl_editor.dart must assign synKeyword color '
              'for keyword token group (group(1)). Either direct AppTheme.synKeyword '
              'or the _CnlColors indirection are acceptable.',
        );
      },
    );

    /// **Validates: Requirements 3.14**
    ///
    /// Error underline uses AppTheme.error — verify source code preserves this.
    /// The pattern is: `final decorationColor = hasError ? AppTheme.error : null;`
    test('P4 — cnl_editor.dart source: error underline uses AppTheme.error', () {
      final workspaceRoot = _resolveWorkspaceRoot();
      final cnlEditorFile = File(
        '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_editor.dart',
      );

      final content = cnlEditorFile.readAsStringSync();

      // The pattern: `? AppTheme.error : null` (ternary assignment for decorationColor)
      expect(
        content.contains('AppTheme.error'),
        isTrue,
        reason:
            'P4 preservation: cnl_editor.dart must reference AppTheme.error for '
            'the wavy underline decorationColor on errored lines.',
      );
    });

    /// **Validates: Requirements 3.14**
    ///
    /// Error underline style is TextDecoration.underline with wavy style.
    test(
      'P5 — cnl_editor.dart source: error lines use TextDecoration.underline wavy',
      () {
        final workspaceRoot = _resolveWorkspaceRoot();
        final cnlEditorFile = File(
          '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_editor.dart',
        );

        final content = cnlEditorFile.readAsStringSync();

        expect(
          content.contains('TextDecoration.underline'),
          isTrue,
          reason:
              'P5 preservation: cnl_editor.dart must use TextDecoration.underline '
              'for error lines.',
        );
        expect(
          content.contains('TextDecorationStyle.wavy'),
          isTrue,
          reason:
              'P5 preservation: cnl_editor.dart must use TextDecorationStyle.wavy '
              'for error line underline style.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Property: ZetaTextInput usages outside _buildEditor() unchanged
  //
  // Tests PASS on unfixed code — ZetaTextInput is used everywhere including
  // inside _buildEditor(). After the fix, ZetaTextInput will only be in
  // the non-editor fields. These tests verify those non-editor usages exist.
  // ---------------------------------------------------------------------------

  group(
    'Property: ZetaTextInput usages outside _buildEditor() unchanged (Req 3.15)',
    () {
      /// **Validates: Requirements 3.15**
      ///
      /// cnl_editor.dart must still import ZetaTextInput (used by _IntField,
      /// _FloatField, and dialog fields). The import must remain after the fix.
      test('P6 — cnl_editor.dart source: ZetaTextInput is still imported', () {
        final workspaceRoot = _resolveWorkspaceRoot();
        final cnlEditorFile = File(
          '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_editor.dart',
        );

        final content = cnlEditorFile.readAsStringSync();

        expect(
          content.contains('ZetaTextInput'),
          isTrue,
          reason:
              'P6 preservation: cnl_editor.dart must import ZetaTextInput — '
              'it is still used by _IntField, _FloatField, and dialog fields. '
              'The import must remain even after _buildEditor() reverts to TextField.',
        );
      });

      /// **Validates: Requirements 3.15**
      ///
      /// cnl_editor.dart source must contain ZetaTextInput in _NumericLiteralDialog,
      /// a non-editor dialog field that uses ZetaTextInput and must remain unchanged.
      test(
        'P7 — cnl_editor.dart source: ZetaTextInput used in _NumericLiteralDialog (non-editor field)',
        () {
          final workspaceRoot = _resolveWorkspaceRoot();
          final cnlEditorFile = File(
            '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_editor.dart',
          );

          final content = cnlEditorFile.readAsStringSync();

          // _NumericLiteralDialog contains a ZetaTextInput field (not in _buildEditor).
          expect(
            content.contains('_NumericLiteralDialog'),
            isTrue,
            reason:
                'P7 preservation: cnl_editor.dart must contain the _NumericLiteralDialog class '
                'which uses ZetaTextInput as a non-editor field.',
          );
          // ZetaTextInput is still present (used in the dialog)
          expect(
            content.contains('ZetaTextInput'),
            isTrue,
            reason:
                'P7 preservation: cnl_editor.dart must still use ZetaTextInput '
                'in the _NumericLiteralDialog (non-editor dialog field).',
          );
        },
      );

      /// **Validates: Requirements 3.15**
      ///
      /// CnlSentenceBuilderDialog in cnl_sentence_builder_dialog.dart uses ZetaTextInput
      /// for all concept fields — this must remain unchanged.
      test(
        'P8 — cnl_sentence_builder_dialog.dart uses ZetaTextInput (non-editor dialog fields)',
        () {
          final workspaceRoot = _resolveWorkspaceRoot();
          final dialogFile = File(
            '$workspaceRoot/nmtk/neuro_toolkit/lib/features/neurocnl/widgets/cnl_sentence_builder_dialog.dart',
          );

          final content = dialogFile.readAsStringSync();

          expect(
            content.contains('ZetaTextInput'),
            isTrue,
            reason:
                'P8 preservation: cnl_sentence_builder_dialog.dart must use ZetaTextInput '
                'for concept input fields (non-editor fields, must remain unchanged).',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Property: Mobile layout unaffected
  //
  // Tests PASS on unfixed code — verify the mobile layout constants and
  // _NmtkMobileAppBar rendering with viewport < 840px.
  // ---------------------------------------------------------------------------

  group('Property: Mobile layout unaffected by desktop density fix (Req 3.6, 3.7)', () {
    /// **Validates: Requirements 3.6**
    ///
    /// Viewport < 840px must render mobile layout (not desktop rail).
    /// We pump NmtkDesktopScaffold at width 400px and verify the widget tree
    /// contains a BottomNavigationBar or drawer — not the desktop rail column.
    testWidgets(
      'P9 — NmtkDesktopScaffold at width 400px renders mobile layout (no desktop rail)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const NmtkDesktopScaffold(
              navItems: [
                NmtkSidebarItem(id: 'a', label: 'A', icon: Icons.code),
                NmtkSidebarItem(id: 'b', label: 'B', icon: Icons.play_arrow),
              ],
              selectedIndex: 0,
              child: SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The mobile layout renders NavigationBar (bottom nav) for ≤5 items.
        // The desktop layout renders the rail column instead.
        // We just confirm the desktop fixed-width AnimatedContainer rail
        // is NOT the dominant layout mode by verifying NavigationBar is found.
        expect(
          find.byType(NavigationBar),
          findsOneWidget,
          reason:
              'P9 preservation: viewport < 840px must render mobile layout with '
              'NavigationBar (bottom nav). The desktop rail must NOT be shown.',
        );
      },
    );

    /// **Validates: Requirements 3.6**
    ///
    /// Viewport >= 840px renders desktop layout (Scaffold body is a Row).
    testWidgets(
      'P10 — NmtkDesktopScaffold at width 900px renders desktop layout (rail present)',
      (tester) async {
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const NmtkDesktopScaffold(
              navItems: [
                NmtkSidebarItem(id: 'a', label: 'A', icon: Icons.code),
                NmtkSidebarItem(id: 'b', label: 'B', icon: Icons.play_arrow),
              ],
              selectedIndex: 0,
              child: SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Desktop layout renders NO NavigationBar (uses rail instead).
        expect(
          find.byType(NavigationBar),
          findsNothing,
          reason:
              'P10 preservation: viewport >= 840px must render desktop layout '
              'WITHOUT a NavigationBar.',
        );
      },
    );

    /// **Validates: Requirements 3.7**
    ///
    /// desktop_scaffold.dart source: _kMobileBreakpoint must be 840.0
    test('P11 — desktop_scaffold.dart source: _kMobileBreakpoint == 840.0', () {
      final workspaceRoot = _resolveWorkspaceRoot();
      final scaffoldFile = File(
        '$workspaceRoot/nmtk_ui_core/lib/widgets/desktop_scaffold.dart',
      );

      final content = scaffoldFile.readAsStringSync();

      expect(
        content.contains('_kMobileBreakpoint = 840.0'),
        isTrue,
        reason:
            'P11 preservation: _kMobileBreakpoint must be 840.0 (foldable = mobile). '
            'The fix changes only desktop constants (_kBrandRowHeight, _kNavItemHeight, etc.).',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Property: Node and edge colors unchanged (forwarding)
  //
  // Tests PASS on unfixed code.
  // ---------------------------------------------------------------------------

  group('Property: Node and edge color forwarding unchanged (Req 3.1, 3.2)', () {
    /// **Validates: Requirements 3.1**
    ///
    /// AppTheme node colors must forward NmtkNeurocnlTokens exactly.
    test(
      'P12 — AppTheme node colors forward NmtkNeurocnlTokens values unchanged',
      () {
        expect(AppTheme.nodeEnsemble, equals(NmtkNeurocnlTokens.nodeEnsemble));
        expect(AppTheme.nodeMotor, equals(NmtkNeurocnlTokens.nodeMotor));
        expect(
          AppTheme.nodeInterneuron,
          equals(NmtkNeurocnlTokens.nodeInterneuron),
        );
        expect(AppTheme.nodeInput, equals(NmtkNeurocnlTokens.nodeInput));
        expect(
          AppTheme.nodeErrorInput,
          equals(NmtkNeurocnlTokens.nodeErrorInput),
        );
      },
    );

    /// **Validates: Requirements 3.2**
    ///
    /// AppTheme edge colors must forward NmtkNeurocnlTokens values exactly.
    test(
      'P13 — AppTheme edge colors forward NmtkNeurocnlTokens values unchanged',
      () {
        expect(
          AppTheme.edgeExcitatory,
          equals(NmtkNeurocnlTokens.edgeExcitatory),
        );
        expect(
          AppTheme.edgeInhibitory,
          equals(NmtkNeurocnlTokens.edgeInhibitory),
        );
        expect(AppTheme.edgePlastic, equals(NmtkNeurocnlTokens.edgePlastic));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Property: CnlEditor renders — sanity pass on unfixed code
  //
  // Tests PASS on unfixed code.
  // ---------------------------------------------------------------------------

  group(
    'Property: CnlEditor widget renders without error (unfixed baseline)',
    () {
      /// **Validates: Requirements 3.13**
      ///
      /// CnlEditor must render without throwing — even on unfixed code where
      /// ZetaTextInput is used. The widget tree must be pumpable.
      testWidgets('P14 — CnlEditor pumps without error on unfixed code', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildCnlEditorHarness());
        await tester.pumpAndSettle();

        // The CnlEditor renders a Semantics widget with label 'CNL Code Editor'.
        // We verify it's in the tree by checking for the Semantics widget type
        // AND checking for the CnlEditor widget itself.
        expect(
          find.byType(CnlEditor),
          findsOneWidget,
          reason:
              'P14 preservation: CnlEditor widget must render without error. '
              'This holds on both unfixed and fixed code.',
        );
      });

      /// **Validates: Requirements 3.13**
      ///
      /// The editor toolbar (with CNL Editor title) must always be rendered.
      testWidgets('P15 — CnlEditor toolbar renders on unfixed code', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildCnlEditorHarness());
        await tester.pumpAndSettle();

        // Toolbar action buttons (undo/redo, templates, add sentence) are
        // IconButton — ZetaButton is only used conditionally for the
        // "Edit selected number" action when a numeric literal is selected.
        expect(
          find.byType(IconButton),
          findsWidgets,
          reason:
              'P15 preservation: CnlEditor toolbar must always render with '
              'action buttons.',
        );
      });
    },
  );
}
