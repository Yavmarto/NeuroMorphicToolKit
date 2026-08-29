import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

const _provenance = StudioResultProvenance(
  workspaceName: 'Session test',
  modelFingerprint: 'model-a',
);

void main() {
  test('successful terminal attempt creates a reviewable snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);

    controller.beginAttempt(
      platforms: const ['snntorch_sim'],
      provenance: _provenance,
    );
    controller.registerJob('snntorch_sim', 'job-1');
    controller.recordEpoch(
      'snntorch_sim',
      const TrainingEpochEvent(epoch: 1, loss: 0.4),
    );
    expect(
      container.read(studioResultSessionProvider).reviewableSnapshot,
      isNull,
    );

    controller.markComplete('snntorch_sim');
    final state = container.read(studioResultSessionProvider);
    expect(state.phase, StudioResultSessionPhase.completed);
    expect(state.reviewableSnapshot, isNotNull);
    expect(
      state.reviewableSnapshot!.platforms['snntorch_sim']!.completedJob!.jobId,
      'job-1',
    );
  });

  test('failed retry keeps the last success available downstream', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);

    controller.beginAttempt(
      platforms: const ['lava_sim'],
      provenance: _provenance,
    );
    controller.registerJob('lava_sim', 'good-job');
    controller.recordEpoch(
      'lava_sim',
      const TrainingEpochEvent(epoch: 1, loss: 0.2),
    );
    controller.markComplete('lava_sim');
    final successful = container
        .read(studioResultSessionProvider)
        .lastSuccessfulSnapshot!;

    controller.beginAttempt(
      platforms: const ['lava_sim'],
      provenance: _provenance,
    );
    expect(
      container.read(studioResultSessionProvider).reviewableSnapshot,
      same(successful),
    );
    controller.markError(
      'lava_sim',
      summary: 'network error',
      detail: 'offline',
    );
    final failed = container.read(studioResultSessionProvider);
    expect(failed.phase, StudioResultSessionPhase.failed);
    expect(failed.lastSuccessfulSnapshot?.id, successful.id);
    expect(failed.reviewableSnapshot?.id, successful.id);
  });

  test('partial attempt retains its snapshot for downstream consumers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);

    controller.beginAttempt(
      platforms: const ['snntorch_sim', 'lava_sim'],
      provenance: _provenance,
    );
    controller.registerJob('snntorch_sim', 'job-1');
    controller.recordEpoch(
      'snntorch_sim',
      const TrainingEpochEvent(epoch: 1, loss: 0.3),
    );
    controller.markComplete('snntorch_sim');
    controller.markError('lava_sim', summary: 'failed');

    expect(
      container.read(studioResultSessionProvider).phase,
      StudioResultSessionPhase.partial,
    );
    expect(
      container.read(studioResultSessionProvider).reviewableSnapshot?.isPartial,
      isTrue,
    );
  });

  test('snapshot JSON is bounded and excludes live attempt state', () {
    final events = List<TrainingEpochEvent>.generate(
      800,
      (index) => TrainingEpochEvent(
        epoch: index,
        loss: 1 / (index + 1),
        phase: index.isEven ? 'train' : 'eval',
      ),
    );
    final legacy = StudioResultSnapshot.fromLegacyHistory(<String, dynamic>{
      'snntorch_sim': events.map((event) => event.toJson()).toList(),
    });
    final restored = StudioResultSnapshot.fromJson(
      Map<String, dynamic>.from(legacy.toJson()),
    );

    expect(
      restored.platforms['snntorch_sim']!.history.length,
      StudioResultSnapshot.maxEventsPerPlatform,
    );
    expect(restored.toJson(), isNot(contains('subscriptions')));
    expect(restored.toJson(), isNot(contains('simulationResults')));
    expect(restored.toJson(), isNot(contains('activeJob')));
  });

  test('selection is carried by the snapshot shared with Deploy', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);
    controller.beginAttempt(
      platforms: const ['lava_sim'],
      provenance: _provenance,
    );
    controller.recordEpoch(
      'lava_sim',
      const TrainingEpochEvent(epoch: 1, loss: 0.1),
    );
    controller.markComplete('lava_sim');
    controller.updateSelection(
      const StudioVisualizationSelection(
        view: StudioResultView.weights,
        platform: 'lava_sim',
        epochIndex: 0,
        layer: 'lif_2',
      ),
    );

    final state = container.read(studioResultSessionProvider);
    expect(state.persistableSnapshot?.selection.view, StudioResultView.weights);
    expect(state.reviewableSnapshot?.selection.layer, 'lif_2');
  });

  test('a completed job reference opens results even without epoch events', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);
    controller.beginAttempt(
      platforms: const ['snntorch_sim'],
      provenance: _provenance,
    );
    controller.registerJob('snntorch_sim', 'details-only-job');
    controller.markComplete('snntorch_sim');

    final state = container.read(studioResultSessionProvider);
    expect(state.phase, StudioResultSessionPhase.completed);
    expect(state.reviewableSnapshot, isNotNull);
    expect(state.reviewableSnapshot!.hasVisualizationData, isTrue);
  });

  test('completion with no events or job stays truthful on the monitor', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);
    controller.beginAttempt(
      platforms: const ['snntorch_sim'],
      provenance: _provenance,
    );
    controller.markComplete('snntorch_sim');

    final state = container.read(studioResultSessionProvider);
    expect(state.phase, StudioResultSessionPhase.completedWithoutResults);
    expect(state.reviewableSnapshot, isNull);
  });

  test('attempt ids invalidate callbacks from an older retry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioResultSessionProvider.notifier);
    controller.beginAttempt(
      platforms: const ['snntorch_sim'],
      provenance: _provenance,
    );
    final oldAttempt = container.read(studioResultSessionProvider).attemptId!;

    controller.beginAttempt(
      platforms: const ['snntorch_sim'],
      provenance: _provenance,
    );
    final currentAttempt = container
        .read(studioResultSessionProvider)
        .attemptId!;
    expect(currentAttempt, isNot(oldAttempt));
    expect(controller.isCurrentAttempt(oldAttempt), isFalse);
    expect(controller.isCurrentAttempt(currentAttempt), isTrue);
  });
}
