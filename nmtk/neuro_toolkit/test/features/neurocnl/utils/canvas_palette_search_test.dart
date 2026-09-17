import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/utils/canvas_palette_search.dart';

class _Item {
  const _Item(this.label, [this.keywords = const <String>[]]);
  final String label;
  final List<String> keywords;
}

const List<_Item> _items = <_Item>[
  _Item('Data Loader', <String>['data', 'labels']),
  _Item('Spike Encoder', <String>['data', 'spikes']),
  _Item('Forward Pass', <String>['input', 'model', 'spikes', 'membrane']),
  _Item('Accuracy', <String>['spikes', 'labels', 'metrics']),
];

List<String> _labels(String query) => filterCanvasPaletteItems<_Item>(
  _items,
  query,
  label: (_Item i) => i.label,
  keywords: (_Item i) => i.keywords,
).map((_Item i) => i.label).toList();

void main() {
  group('canvasPaletteMatchScore', () {
    test('a blank query matches everything, so callers need no empty-case', () {
      expect(canvasPaletteMatchScore(query: '   ', label: 'Data Loader'), 0);
    });

    test('exact beats prefix beats substring', () {
      expect(canvasPaletteMatchScore(query: 'accuracy', label: 'Accuracy'), 0);
      expect(canvasPaletteMatchScore(query: 'acc', label: 'Accuracy'), 1);
      expect(canvasPaletteMatchScore(query: 'pass', label: 'Forward Pass'), 2);
    });

    test('matching is case-insensitive', () {
      expect(canvasPaletteMatchScore(query: 'DATA', label: 'Data Loader'), 1);
    });

    test('a keyword match ranks below every label match', () {
      final int keywordScore = canvasPaletteMatchScore(
        query: 'spikes',
        label: 'Accuracy',
        keywords: const <String>['spikes', 'labels'],
      );
      expect(keywordScore, 3);
      expect(
        keywordScore,
        greaterThan(canvasPaletteMatchScore(query: 'acc', label: 'Accuracy')),
      );
    });

    test('a near-miss typo still matches, fuzzily', () {
      final int score = canvasPaletteMatchScore(
        query: 'accuracey',
        label: 'Accuracy',
      );
      expect(score, greaterThan(3));
      expect(score, isNot(kCanvasPaletteNoMatch));
    });

    test('an unrelated query matches nothing', () {
      expect(
        canvasPaletteMatchScore(query: 'zzzzzzzz', label: 'Accuracy'),
        kCanvasPaletteNoMatch,
      );
    });

    test('fuzzy does not run over keywords', () {
      // 'spike' → 'spikes' is distance 1, but keyword matching is substring
      // only. A three-typo query against a keyword must not match, or nearly
      // any node would match nearly any query via some port id.
      expect(
        canvasPaletteMatchScore(
          query: 'spykez',
          label: 'Accuracy',
          keywords: const <String>['spikes'],
        ),
        kCanvasPaletteNoMatch,
      );
    });
  });

  group('filterCanvasPaletteItems', () {
    test('an empty query returns every item in the original order', () {
      expect(_labels(''), <String>[
        'Data Loader',
        'Spike Encoder',
        'Forward Pass',
        'Accuracy',
      ]);
    });

    test('narrows to label matches', () {
      expect(_labels('loader'), <String>['Data Loader']);
    });

    test('a port-id query surfaces nodes whose label says nothing of it', () {
      // 'membrane' appears only as a port of Forward Pass.
      expect(_labels('membrane'), <String>['Forward Pass']);
    });

    test('label matches outrank port matches for the same query', () {
      // 'Spike Encoder' matches by label; Forward Pass and Accuracy only by
      // their `spikes` ports.
      expect(_labels('spike').first, 'Spike Encoder');
      expect(_labels('spike'), containsAll(<String>['Accuracy']));
    });

    test('ties keep the palette\'s deliberate ordering', () {
      // Both match 'data' by keyword only, at identical score.
      expect(_labels('labels'), <String>['Data Loader', 'Accuracy']);
    });

    test('no match yields an empty list, not the full list', () {
      expect(_labels('zzzzzzzz'), isEmpty);
    });
  });
}
