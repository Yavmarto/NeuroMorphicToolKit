import 'package:riverpod_annotation/riverpod_annotation.dart';
// Structure test for the Parse-results migration.
//
// History:
// * `zeta-card-unification Task 5` originally wrapped every parsed-sentence
//   row in [NmtkItemCard] so all list rows shared a unified card surface.
//   The test below was named for that direction.
// * `zeta-card-reduction Task 9` reverses that direction — `NmtkItemCard`
//   is on its way to deletion (T12), and each row migrates to
//   [ZetaListItem] (matching the validation panel's failure rows). The
//   `zeta-card-reduction Task 10` migration also flips the section header
//   from [NeurocnlSectionCard] → [NmtkSection].
//
// The assertions therefore lock the *new* flat shape:
//
//   1. Each parsed-sentence row renders as exactly one [ZetaListItem].
//   2. The "x/y parsed successfully" header renders as an [NmtkSection]
//      (not [NeurocnlSectionCard], not [NmtkSurfaceCard]).
//   3. No row subtree may contain a Material `Card`, [NmtkSurfaceCard],
//      [NmtkItemCard], or a raw `Container`/`Ink` whose `BoxDecoration`
//      carries both a non-null `color` and a non-null `borderRadius`
//      (the historical "hand-rolled card" pattern).
//
// Future edits cannot reintroduce a divergent row treatment.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/error_detail.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/parse_results_table.dart';

const ParseResult _mixedFixture = ParseResult(
  sentences: [
    ParseSentence(
      line: 11,
      raw: 'Define a Input named input.',
      valid: true,
      parsed: ParsedSpec(
        subject: 'input',
        concept: 'Input',
        action: 'Define',
        verb: 'is',
        negated: false,
      ),
    ),
    ParseSentence(
      line: 12,
      raw: 'Define a LIF named sensor.',
      valid: true,
      parsed: ParsedSpec(
        subject: 'sensor',
        concept: 'LIF',
        action: 'Define',
        verb: 'is',
        negated: false,
      ),
    ),
    ParseSentence(
      line: 13,
      raw: 'Make a neuron that goes zap fast.',
      valid: false,
      error: 'Unsupported sentence family.',
      errorDetail: ErrorDetail(
        code: 'unsupported_sentence_family',
        message: 'Unsupported sentence family.',
        line: 13,
      ),
    ),
  ],
  total: 3,
  errors: 1,
);

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: ZetaProvider(
      initialContrast: ZetaContrast.aa,
      initialThemeMode: ThemeMode.dark,
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 800, height: 600, child: ParseResultsTable()),
        ),
      ),
    ),
  );
}

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: <Override>[
      pipelineProvider.overrideWith(
        () => _FakePipelineController(
          const PipelineState(parseResult: _mixedFixture),
        ),
      ),
    ],
  );
}

bool _hasFilledRoundedDecoration(BoxDecoration? decoration) {
  if (decoration == null) return false;
  return decoration.color != null && decoration.borderRadius != null;
}

bool _isCardLikeDecoratedSurface(Widget widget) {
  if (widget is Container) {
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        _hasFilledRoundedDecoration(decoration);
  }
  if (widget is Ink) {
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        _hasFilledRoundedDecoration(decoration);
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

  testWidgets('ParseResultsTable header renders as NmtkStatusBanner', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    // Two pumps — keeps Zeta widgets settled without a pumpAndSettle
    // timeout (handoff §3.2).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Commit 6b52a256 ("feat: convert training to pane, add parse status
    // card, remove play button") replaced the NmtkSection header with an
    // NmtkStatusBanner; the title format for a partial-error fixture is
    // "<n> parse error(s) — <ok>/<total> sentences valid".
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is NmtkStatusBanner &&
            widget.title == '1 parse error — 2/3 sentences valid',
        description:
            'NmtkStatusBanner(title: "1 parse error — 2/3 sentences valid")',
      ),
      findsOneWidget,
      reason:
          'ParseResultsTable header must use NmtkStatusBanner '
          '(commit 6b52a256). Re-introduction of the deleted '
          'NeurocnlSectionCard is enforced at source level by the T13 '
          'governance tests.',
    );
  });

  testWidgets('ParseResultsTable renders one ZetaListItem per parse sentence', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 3 sentences in fixture → exactly 3 ZetaListItems in the row list.
    // The header is an NmtkSection (no ZetaListItem), so it isn't counted.
    expect(
      find.byType(ZetaListItem),
      findsNWidgets(3),
      reason:
          'Each parse-sentence row must be wrapped by exactly one '
          'ZetaListItem (zeta-card-reduction Task 9). Re-introduction of '
          'the deleted NmtkItemCard wrapper is enforced at source level '
          'by the T13 governance tests.',
    );
  });

  testWidgets(
    'No parse row uses Material Card, NmtkSurfaceCard, or hand-rolled card surface',
    (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final Finder rootFinder = find.byType(ParseResultsTable);

      // No NmtkSurfaceCard / Material Card anywhere in the table subtree.
      expect(
        find.descendant(of: rootFinder, matching: find.byType(NmtkSurfaceCard)),
        findsNothing,
        reason:
            'ParseResultsTable subtree must not contain any NmtkSurfaceCard '
            '(zeta-card-reduction Tasks 9 + 10 — flat).',
      );
      expect(
        find.descendant(of: rootFinder, matching: find.byType(Card)),
        findsNothing,
        reason: 'ParseResultsTable subtree must not contain any Material Card.',
      );

      // Each ZetaListItem subtree must remain flat.
      final Finder listItems = find.descendant(
        of: rootFinder,
        matching: find.byType(ZetaListItem),
      );
      expect(listItems, findsNWidgets(3));

      for (final Element listItemElement in listItems.evaluate()) {
        final Finder listItemFinder = find.byWidget(listItemElement.widget);

        expect(
          find.descendant(
            of: listItemFinder,
            matching: find.byType(NmtkSurfaceCard),
          ),
          findsNothing,
          reason:
              'No ZetaListItem in ParseResultsTable may wrap an '
              'NmtkSurfaceCard.',
        );
        expect(
          find.descendant(
            of: listItemFinder,
            matching: find.byWidgetPredicate(
              _isCardLikeDecoratedSurface,
              description:
                  'Container/Ink with BoxDecoration{color, borderRadius}',
            ),
          ),
          findsNothing,
          reason:
              'No ZetaListItem in ParseResultsTable may host a '
              'Container/Ink with BoxDecoration{color, borderRadius} — '
              'that pattern is the historical "hand-rolled card" the '
              'reduction removes.',
        );
      }
    },
  );
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
