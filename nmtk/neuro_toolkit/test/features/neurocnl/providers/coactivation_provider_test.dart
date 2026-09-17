// Tests for the CEL-140 co-activation provider: live ingestion from
// training_mode_provider, explicit review-mode load/reset, and the derived
// correlation snapshot the network view consumes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/coactivation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';

PreviewPlayback _playback() {
  return const PreviewPlayback(
    durationMs: 500,
    nodes: <PreviewNodePlayback>[
      PreviewNodePlayback(
        nodeId: 'a',
        spikeTrains: <String, List<double>>{
          '0': <double>[0, 50, 100, 150, 200],
        },
      ),
      PreviewNodePlayback(
        nodeId: 'b',
        spikeTrains: <String, List<double>>{
          '0': <double>[0, 50, 100, 150, 200],
        },
      ),
    ],
  );
}

void main() {
  test('ingests live rates and produces a correlation snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(coactivationProvider, (_, _) {}, fireImmediately: true);

    final training = container.read(trainingModeProvider.notifier);
    for (var i = 0; i < 12; i += 1) {
      training.setRates(<String, double>{
        'a': i.toDouble(),
        'b': i.toDouble(),
        'c': (12 - i).toDouble(),
      });
    }

    final state = container.read(coactivationProvider);
    expect(state.snapshot, isNotNull);
    expect(state.snapshot!.correlation('a', 'b'), closeTo(1.0, 1e-6));
    expect(state.snapshot!.correlation('a', 'c'), closeTo(-1.0, 1e-6));
    expect(state.isReview, isFalse);
  });

  test('loadPlayback enters review mode and reset returns to live', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(coactivationProvider, (_, _) {}, fireImmediately: true);

    final notifier = container.read(coactivationProvider.notifier);
    notifier.loadPlayback(_playback());

    final review = container.read(coactivationProvider);
    expect(review.isReview, isTrue);
    expect(review.reviewRates, isNotNull);
    expect(review.snapshot, isNotNull);
    expect(review.snapshot!.correlation('a', 'b')!, greaterThan(0.5));

    notifier.reset();
    final live = container.read(coactivationProvider);
    expect(live.isReview, isFalse);
    expect(live.snapshot, isNull);
  });

  test('review mode ignores later live writes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(coactivationProvider, (_, _) {}, fireImmediately: true);

    final notifier = container.read(coactivationProvider.notifier);
    notifier.loadPlayback(_playback());
    final before = container.read(coactivationProvider).snapshot;

    container.read(trainingModeProvider.notifier).setRates(
      const <String, double>{'a': 1, 'b': 0},
    );

    final after = container.read(coactivationProvider);
    expect(after.isReview, isTrue);
    expect(identical(after.snapshot, before), isTrue);
  });

  test('seeds review mode from a playback already present at build', () {
    final container = ProviderContainer(
      overrides: [
        simulationProvider.overrideWithValue(
          SimulationState(playback: _playback()),
        ),
      ],
    );
    addTearDown(container.dispose);

    // The provider is never told to load a playback: it must discover the
    // already-present playback on first build.
    final state = container.read(coactivationProvider);
    expect(state.isReview, isTrue);
    expect(state.reviewRates, isNotNull);
    expect(state.snapshot!.correlation('a', 'b')!, greaterThan(0.5));
  });

  test('seeds live mode from rates already streaming at build', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(coactivationProvider, (_, _) {}, fireImmediately: true);

    // A live tick lands before the co-activation provider is first read.
    container.read(trainingModeProvider.notifier).setRates(
      const <String, double>{'a': 1, 'b': 1, 'c': 0},
    );
    final seeded = container.read(coactivationProvider);
    expect(seeded.isReview, isFalse);

    // The seeded tick counts; later ticks flow through the listener.
    for (var i = 0; i < 10; i += 1) {
      container.read(trainingModeProvider.notifier).setRates(<String, double>{
        'a': i.toDouble(),
        'b': i.toDouble(),
        'c': (10 - i).toDouble(),
      });
    }
    final grown = container.read(coactivationProvider);
    expect(grown.snapshot, isNotNull);
    expect(grown.snapshot!.correlation('a', 'b'), closeTo(1.0, 1e-6));
    expect(grown.snapshot!.correlation('a', 'c'), lessThan(0.0));
  });
}
