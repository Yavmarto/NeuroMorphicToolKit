import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step_logic.dart';

void main() {
  test('allSucceeded is false when any platform errored', () {
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.complete,
      'nengo': TrainingRunOutcome.error,
    };
    expect(RunStepLogic.allSucceeded(flags), isFalse);
    expect(RunStepLogic.hasAnyError(flags), isTrue);
  });

  test('allSucceeded is true only when every platform completed', () {
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.complete,
    };
    expect(RunStepLogic.allSucceeded(flags), isTrue);
    expect(RunStepLogic.hasAnyError(flags), isFalse);
  });

  test('a deploy-only platform does not block the success banner', () {
    // Akida is never run — it has no training adapter — so requiring it to be
    // `complete` would hide the success banner for every run that has one
    // selected, which is what made ticking Akida look like a mistake.
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.complete,
      'akida': TrainingRunOutcome.notApplicable,
    };
    expect(RunStepLogic.allSucceeded(flags), isTrue);
    expect(RunStepLogic.hasAnyError(flags), isFalse);
  });

  test('notApplicable is not success on its own', () {
    // Nothing actually ran, so there is nothing to congratulate.
    final flags = <String, TrainingRunOutcome>{
      'akida': TrainingRunOutcome.notApplicable,
    };
    expect(RunStepLogic.allSucceeded(flags), isFalse);
    expect(RunStepLogic.hasAnyError(flags), isFalse);
  });

  test('a real error still wins over a deploy-only platform', () {
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.error,
      'akida': TrainingRunOutcome.notApplicable,
    };
    expect(RunStepLogic.allSucceeded(flags), isFalse);
    expect(RunStepLogic.hasAnyError(flags), isTrue);
  });

  test('dataset upload preparation runs only when regenerating', () {
    expect(
      RunStepLogic.shouldPrepareDatasets(
        keepEditedNotebook: false,
        cancelled: false,
      ),
      isTrue,
    );
    expect(
      RunStepLogic.shouldPrepareDatasets(
        keepEditedNotebook: true,
        cancelled: false,
      ),
      isFalse,
    );
    expect(
      RunStepLogic.shouldPrepareDatasets(
        keepEditedNotebook: false,
        cancelled: true,
      ),
      isFalse,
    );
  });

  test('only a busy matching Jupyter session blocks an automated run', () {
    const notebookPath = 'demo/notebooks/pipeline_snntorch_sim.ipynb';
    final sessions = <Map<String, dynamic>>[
      {
        'path': notebookPath,
        'kernel': {'execution_state': 'starting'},
      },
      {
        'path': 'other/notebook.ipynb',
        'kernel': {'execution_state': 'busy'},
      },
    ];

    expect(hasExecutingJupyterSessionForPath(sessions, notebookPath), isFalse);

    sessions.add({
      'path': notebookPath,
      'kernel': {'execution_state': 'busy'},
    });
    expect(hasExecutingJupyterSessionForPath(sessions, notebookPath), isTrue);
  });
}
