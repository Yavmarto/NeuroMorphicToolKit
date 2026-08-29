// Widget tests — PipelineNodePropertyPanel Data Loader race regression
//
// **Validates: Task 0 — the Data Loader inspector parameter-loss bug.**
//
// Root cause (see `.superpowers/sdd/task-0-brief.md` / task-0-report.md):
// `_DataLoaderFields.build()` captures `final p = node.parameters;` once per
// build. Every sibling field's commit closure closes over that SAME `p`
// snapshot until the widget rebuilds with fresh state. If two sibling field
// commits land back-to-back with no rebuild in between, and the provider (or
// the widget) sends a full `{...p, key: value}` snapshot instead of a
// single-key delta, the second commit's stale copy of the first field's key
// silently reverts the just-committed value.
//
// This test drives the REAL widget tree end to end (real `DropdownButtonFormField`
// / `CanvasParameterTextField` / `Switch` instances built by the actual
// `PipelineNodePropertyPanel` -> `_DataLoaderFields` widgets, found via the
// `ValueKey('${node.id}__param__$paramName')` keys), then invokes each
// field's real `onChanged`/`onCommit` callback directly rather than
// simulating raw pointer/keyboard gestures.
//
// Why not drive this purely through `tester.enterText` / `tester.tap`?
// `Format` is a `DropdownButtonFormField`, whose popup menu lives in an
// Overlay route with its own open/close animation — reliably tapping a menu
// item without an intervening `pumpAndSettle()` (which would rebuild
// `_DataLoaderFields` and refresh the captured `p`, hiding the bug) is not
// practical in the widget-test harness. Fetching the actual widget instance
// via `tester.widget<...>(find.byKey(...))` and invoking its callback
// directly still exercises the real callback chain all the way down to
// `ref.read(canvasProvider.notifier).updatePipelineDagNodeParams(...)` — it
// just skips simulating the pointer/animation choreography needed to open
// the dropdown, and skips `CanvasParameterTextField`'s internal debounce
// Timer (which only delays *when* `onCommit` fires, not *what* it's called
// with). This is flagged explicitly per the review's guidance to report
// (rather than silently paper over) any place a literal debounce-timing
// race could not be reproduced pixel-for-pixel.
//
// Tests:
//   Case A — Format -> Dataset Path -> Batch Size (ends on Batch Size).
//   Case B — Format -> Dataset Path -> Shuffle (ends on Shuffle).
//   Both assert every key coexists afterwards, including the untouched
//   default `shuffle: true` seeded via `PipelineDagNodeType.dataLoader
//   .defaultParameters` (matching how `addPipelineDagNode` actually seeds
//   new nodes in production — see `pipeline_phase_canvas.dart`).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' as app_api;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_node_property_panel.dart';

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<String> generateCnl(CanvasGraph graph) async => '';

  @override
  Future<CanvasGraph> repairCnl(String cnl, {CanvasGraph? graph}) async =>
      graph ??
      CanvasGraph(nodes: const [], edges: const [], metadata: const {});

  @override
  Future<ImportNirBytesResponse> importNirBytes(Uint8List payload) async =>
      ImportNirBytesResponse(
        graph: CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        ),
      );

  @override
  Future<Uint8List> exportNirBytes(CanvasGraph graph) async => Uint8List(0);

  @override
  Future<String> generateCnlFromNirBytes(Uint8List payload) async => '';
}

PipelineDagNode _dataLoaderNode(String id) => PipelineDagNode(
  id: id,
  type: PipelineDagNodeType.dataLoader,
  // Matches how `pipeline_phase_canvas.dart` actually seeds a dropped node
  // (`parameters: details.data.defaultParameters`) so `shuffle: true` etc.
  // are present in `node.parameters` from the start, not just as a UI
  // fallback default.
  parameters: Map<String, dynamic>.from(
    PipelineDagNodeType.dataLoader.defaultParameters,
  ),
);

PipelineDagNode _validationLoopNode(String id) => PipelineDagNode(
  id: id,
  type: PipelineDagNodeType.validationLoop,
  // Same seeding convention as _dataLoaderNode above: real nodes get their
  // parameters populated from defaultParameters at drop-time, not just via
  // UI-side fallbacks.
  parameters: Map<String, dynamic>.from(
    PipelineDagNodeType.validationLoop.defaultParameters,
  ),
);

PipelineDagNode _testLoaderNode(String id) => PipelineDagNode(
  id: id,
  type: PipelineDagNodeType.testLoader,
  // Same seeding convention as _dataLoaderNode above.
  parameters: Map<String, dynamic>.from(
    PipelineDagNodeType.testLoader.defaultParameters,
  ),
);

PipelineDagNode _forwardPassNode(String id) => PipelineDagNode(
  id: id,
  type: PipelineDagNodeType.forwardPass,
  parameters: Map<String, dynamic>.from(
    PipelineDagNodeType.forwardPass.defaultParameters,
  ),
);

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  return container;
}

Widget _buildApp(
  ProviderContainer container, {
  PipelinePhaseId phase = PipelinePhaseId.train,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: PipelineNodePropertyPanel(phase: phase),
        ),
      ),
    ),
  );
}

Widget _buildPipelineCanvasApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 900,
          child: PipelinePhaseCanvas(phase: PipelinePhaseId.train),
        ),
      ),
    ),
  );
}

DropdownButtonFormField<String> _dropdownFor(WidgetTester tester, Key key) =>
    tester.widget<DropdownButtonFormField<String>>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );

CanvasParameterTextField _textFieldFor(WidgetTester tester, Key key) =>
    tester.widget<CanvasParameterTextField>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(CanvasParameterTextField),
      ),
    );

Switch _switchFor(WidgetTester tester, Key key) => tester.widget<Switch>(
  find.descendant(of: find.byKey(key), matching: find.byType(Switch)),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('pipeline drag target is bounded to the visible viewport', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildPipelineCanvasApp(container));
    await tester.pump();

    final canvas = find.byType(PipelinePhaseCanvas);
    final dragTarget = find.byType(DragTarget<PipelineDagNodeType>);
    expect(tester.getSize(dragTarget), tester.getSize(canvas));

    await tester.tapAt(tester.getCenter(canvas));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  group('Data Loader inspector — sequential-commit race (Task 0)', () {
    testWidgets(
      'Case A: Format -> Dataset Path -> Batch Size all coexist afterwards',
      (WidgetTester tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _dataLoaderNode('dl_case_a');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.train, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        final formatKey = ValueKey('${node.id}__param__format');
        final datasetPathKey = ValueKey('${node.id}__param__dataset_path');
        final batchSizeKey = ValueKey('${node.id}__param__batch_size');

        // Step 1: commit Format -> 'pt' via the real DropdownButtonFormField
        // built by _DataLoaderFields's FIRST build (parameters == defaults).
        _dropdownFor(tester, formatKey).onChanged!('pt');

        // Exactly ONE rebuild: required so the Dataset Path field (only
        // rendered when format is 'pt'/'npy') actually mounts. This is the
        // only rebuild allowed before the race below -- both fields fetched
        // next come from this SAME `_DataLoaderFields.build()` call, so both
        // of their onCommit closures close over the identical `p` snapshot
        // (which already contains format: 'pt', per the fix under test).
        await tester.pump();

        final datasetPathField = _textFieldFor(tester, datasetPathKey);
        final batchSizeField = _textFieldFor(tester, batchSizeKey);

        // Step 2 then 3, back-to-back, with NO pump() in between: this is
        // the exact race from the brief. On the old blind-replace provider
        // (or the old whole-map-snapshot widget closures), step 3's payload
        // still carries the stale pre-edit `dataset_path` (empty string)
        // captured in the SAME `p` as step 2, silently reverting step 2's
        // just-committed value.
        datasetPathField.onCommit('paper/03_rnn/data/ds_train.pt');
        batchSizeField.onCommit('64');

        await tester.pumpAndSettle();

        final resultNode = container
            .read(canvasProvider)
            .pipelinePhases
            .train
            .nodes
            .firstWhere((n) => n.id == node.id);

        expect(
          resultNode.parameters['format'],
          equals('pt'),
          reason: 'Format committed first must survive later sibling commits.',
        );
        expect(
          resultNode.parameters['dataset_path'],
          equals('paper/03_rnn/data/ds_train.pt'),
          reason:
              'Dataset Path must survive the immediately-following Batch '
              'Size commit sharing the same stale build-time snapshot.',
        );
        expect(
          resultNode.parameters['batch_size'],
          equals(64),
          reason: 'Batch Size (the last commit) must be applied.',
        );
        expect(
          resultNode.parameters['shuffle'],
          isTrue,
          reason:
              'shuffle was never touched by any commit in this race and '
              'must still hold its seeded default (true).',
        );
      },
    );

    testWidgets(
      'Case B: Format -> Dataset Path -> Shuffle all coexist afterwards',
      (WidgetTester tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _dataLoaderNode('dl_case_b');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.train, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        final formatKey = ValueKey('${node.id}__param__format');
        final datasetPathKey = ValueKey('${node.id}__param__dataset_path');
        final shuffleKey = ValueKey('${node.id}__param__shuffle');

        _dropdownFor(tester, formatKey).onChanged!('pt');
        await tester.pump();

        final datasetPathField = _textFieldFor(tester, datasetPathKey);
        final shuffleSwitch = _switchFor(tester, shuffleKey);

        datasetPathField.onCommit('paper/03_rnn/data/ds_train.pt');
        shuffleSwitch.onChanged!(false);

        await tester.pumpAndSettle();

        final resultNode = container
            .read(canvasProvider)
            .pipelinePhases
            .train
            .nodes
            .firstWhere((n) => n.id == node.id);

        expect(
          resultNode.parameters['format'],
          equals('pt'),
          reason: 'Format committed first must survive later sibling commits.',
        );
        expect(
          resultNode.parameters['dataset_path'],
          equals('paper/03_rnn/data/ds_train.pt'),
          reason:
              'Dataset Path must survive the immediately-following Shuffle '
              'commit sharing the same stale build-time snapshot.',
        );
        expect(
          resultNode.parameters['shuffle'],
          isFalse,
          reason: 'Shuffle (the last commit) must be applied.',
        );
        expect(
          resultNode.parameters['batch_size'],
          equals(32),
          reason:
              'batch_size was never touched by any commit in this race and '
              'must still hold its seeded default (32).',
        );
      },
    );
  });

  group('Validation Loop inspector (Task 5)', () {
    testWidgets('Every N Epochs -> Save Best Checkpoint off coexist, '
        'and Checkpoint Metric/Mode fields disappear', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final node = _validationLoopNode('vl_case_a');
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, node);
      container.read(canvasProvider.notifier).selectNode(node.id);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      final everyNKey = ValueKey('${node.id}__param__every_n_epochs');
      final saveBestKey = ValueKey('${node.id}__param__save_best_checkpoint');
      final metricKey = ValueKey('${node.id}__param__checkpoint_metric');
      final modeKey = ValueKey('${node.id}__param__checkpoint_mode');

      // Checkpoint Metric/Mode are visible by default
      // (save_best_checkpoint defaults to true).
      expect(find.byKey(metricKey), findsOneWidget);
      expect(find.byKey(modeKey), findsOneWidget);

      final everyNField = _textFieldFor(tester, everyNKey);
      final saveBestSwitch = _switchFor(tester, saveBestKey);

      // Two sibling commits back-to-back, no pump() in between -- same
      // stale-snapshot race shape as Task 0's Data Loader case, but here
      // the second commit (the switch) also changes which fields are
      // conditionally rendered.
      everyNField.onCommit('2');
      saveBestSwitch.onChanged!(false);

      await tester.pumpAndSettle();

      expect(
        find.byKey(metricKey),
        findsNothing,
        reason:
            'Checkpoint Metric must hide once Save Best Checkpoint is '
            'off.',
      );
      expect(
        find.byKey(modeKey),
        findsNothing,
        reason:
            'Checkpoint Mode must hide once Save Best Checkpoint is '
            'off.',
      );

      final resultNode = container
          .read(canvasProvider)
          .pipelinePhases
          .train
          .nodes
          .firstWhere((n) => n.id == node.id);

      expect(
        resultNode.parameters['every_n_epochs'],
        equals(2),
        reason:
            'Validate Every N Epochs committed first must survive the '
            'immediately following Save Best Checkpoint commit sharing '
            'the same stale build-time snapshot.',
      );
      expect(
        resultNode.parameters['save_best_checkpoint'],
        isFalse,
        reason: 'Save Best Checkpoint (the last commit) must be applied.',
      );
      // Hidden fields retain their underlying values even though the
      // widgets are gone from the tree.
      expect(
        resultNode.parameters['checkpoint_metric'],
        equals('val_accuracy'),
      );
      expect(resultNode.parameters['checkpoint_mode'], equals('max'));
    });

    testWidgets(
      'toggling Save Best Checkpoint back on reveals Checkpoint Metric/Mode '
      'again, and committing them preserves Every N Epochs',
      (WidgetTester tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _validationLoopNode('vl_case_b');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.train, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        final saveBestKey = ValueKey('${node.id}__param__save_best_checkpoint');
        final metricKey = ValueKey('${node.id}__param__checkpoint_metric');
        final modeKey = ValueKey('${node.id}__param__checkpoint_mode');

        // Toggle off then back on.
        _switchFor(tester, saveBestKey).onChanged!(false);
        await tester.pumpAndSettle();
        expect(find.byKey(metricKey), findsNothing);
        expect(find.byKey(modeKey), findsNothing);

        _switchFor(tester, saveBestKey).onChanged!(true);
        await tester.pumpAndSettle();
        expect(
          find.byKey(metricKey),
          findsOneWidget,
          reason:
              'Checkpoint Metric must reappear once Save Best '
              'Checkpoint is back on.',
        );
        expect(
          find.byKey(modeKey),
          findsOneWidget,
          reason:
              'Checkpoint Mode must reappear once Save Best Checkpoint '
              'is back on.',
        );

        _dropdownFor(tester, metricKey).onChanged!('val_loss');
        _dropdownFor(tester, modeKey).onChanged!('min');
        await tester.pumpAndSettle();

        final resultNode = container
            .read(canvasProvider)
            .pipelinePhases
            .train
            .nodes
            .firstWhere((n) => n.id == node.id);

        expect(resultNode.parameters['save_best_checkpoint'], isTrue);
        expect(resultNode.parameters['checkpoint_metric'], equals('val_loss'));
        expect(resultNode.parameters['checkpoint_mode'], equals('min'));
      },
    );
  });

  group(
    'Forward Pass inspector — phase-derived Eval Mode indicator (Task 6)',
    () {
      testWidgets('train phase renders "Off (train phase)"', (
        WidgetTester tester,
      ) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _forwardPassNode('fp_train');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.train, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(
          _buildApp(container, phase: PipelinePhaseId.train),
        );
        await tester.pumpAndSettle();

        expect(find.text('Off (train phase)'), findsOneWidget);
        expect(find.text('Confirmed (eval phase)'), findsNothing);
      });

      testWidgets('eval phase renders "Confirmed (eval phase)"', (
        WidgetTester tester,
      ) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _forwardPassNode('fp_eval');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.eval, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(
          _buildApp(container, phase: PipelinePhaseId.eval),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirmed (eval phase)'), findsOneWidget);
        expect(find.text('Off (train phase)'), findsNothing);
      });
    },
  );

  group('Test Loader inspector — Load Best Checkpoint (Task 6)', () {
    testWidgets(
      'toggling Load Best Checkpoint commits and coexists with a sibling '
      'Batch Size commit sharing the same stale build-time snapshot',
      (WidgetTester tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final node = _testLoaderNode('tl_case_a');
        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.eval, node);
        container.read(canvasProvider.notifier).selectNode(node.id);

        await tester.pumpWidget(
          _buildApp(container, phase: PipelinePhaseId.eval),
        );
        await tester.pumpAndSettle();

        final loadBestKey = ValueKey('${node.id}__param__load_best_checkpoint');
        final batchSizeKey = ValueKey('${node.id}__param__batch_size');

        expect(find.byKey(loadBestKey), findsOneWidget);

        final loadBestSwitch = _switchFor(tester, loadBestKey);
        final batchSizeField = _textFieldFor(tester, batchSizeKey);

        // Same race shape as Task 0's Data Loader case: two sibling commits
        // back-to-back with no pump() in between.
        loadBestSwitch.onChanged!(false);
        batchSizeField.onCommit('64');

        await tester.pumpAndSettle();

        final resultNode = container
            .read(canvasProvider)
            .pipelinePhases
            .eval
            .nodes
            .firstWhere((n) => n.id == node.id);

        expect(
          resultNode.parameters['load_best_checkpoint'],
          isFalse,
          reason:
              'Load Best Checkpoint (committed first) must survive the '
              'immediately-following Batch Size commit sharing the same '
              'stale build-time snapshot.',
        );
        expect(
          resultNode.parameters['batch_size'],
          equals(64),
          reason: 'Batch Size (the last commit) must be applied.',
        );
        expect(
          resultNode.parameters['shuffle'],
          isFalse,
          reason:
              'shuffle was never touched by any commit in this race and '
              'must still hold its seeded testLoader default (false).',
        );
      },
    );

    testWidgets('Data Loader (not Test Loader) does not render the Load Best '
        'Checkpoint switch', (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final node = _dataLoaderNode('dl_no_checkpoint_switch');
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, node);
      container.read(canvasProvider.notifier).selectNode(node.id);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      final loadBestKey = ValueKey('${node.id}__param__load_best_checkpoint');
      expect(find.byKey(loadBestKey), findsNothing);
    });
  });

  group('PipelineNodePropertyPanel — never renders blank', () {
    testWidgets('selected training node exposes Python source', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final node = _dataLoaderNode('source-node');
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, node);
      container.read(canvasProvider.notifier).selectNode(node.id);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('View Python'), findsOneWidget);
    });

    testWidgets('shows a placeholder when nothing is selected', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(
        find.text('Select a node to inspect its parameters.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a multi-select summary instead of going blank', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final nodeA = _dataLoaderNode('multi_a');
      final nodeB = _testLoaderNode('multi_b');
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, nodeA);
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, nodeB);
      container.read(canvasProvider.notifier).selectNodes({nodeA.id, nodeB.id});

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('2 nodes selected'), findsOneWidget);
    });
  });

  group('DatasetPathField browse button', () {
    testWidgets('node stores client metadata until generation', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final node = _dataLoaderNode('local-file-node').copyWith(
        parameters: <String, dynamic>{
          ...PipelineDagNodeType.dataLoader.defaultParameters,
          'format': 'pt',
        },
      );
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(PipelinePhaseId.train, node);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      final field = tester.widget<DatasetPathField>(
        find.byType(DatasetPathField),
      );
      field.onFileSelected(
        PickedFileData(
          name: 'mnist.pt',
          path: '/local/mnist.pt',
          bytes: Uint8List(0),
        ),
      );

      final updated = container
          .read(canvasProvider)
          .pipelinePhases
          .train
          .nodes
          .single;
      expect(updated.parameters['dataset_path'], '/local/mnist.pt');
      expect(updated.parameters[kDatasetPathScopeKey], kClientDatasetPathScope);
      expect(updated.parameters[kDatasetFileNameKey], 'mnist.pt');

      field.onChanged('/server/manual.pt');
      final manuallyUpdated = container
          .read(canvasProvider)
          .pipelinePhases
          .train
          .nodes
          .single;
      expect(manuallyUpdated.parameters['dataset_path'], '/server/manual.pt');
      expect(
        manuallyUpdated.parameters[kDatasetPathScopeKey],
        kServerDatasetPathScope,
      );
      expect(manuallyUpdated.parameters[kDatasetFileNameKey], isEmpty);
    });

    testWidgets('picking a file stages its path without uploading', (
      WidgetTester tester,
    ) async {
      final gateway = _FakeNativeFileDialogGateway(
        pickFilesResult: <PickedFileData>[
          PickedFileData(
            name: 'ds.pt',
            path: '/some/picked/ds.pt',
            bytes: Uint8List(0),
          ),
        ],
      );
      final fakeApi = _FakeApiClient();
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);
      PickedFileData? selected;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: DatasetPathField(
                value: '',
                format: 'pt',
                onChanged: (_) {},
                onFileSelected: (file) => selected = file,
                gateway: gateway,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(ZetaIcons.folder_outline));
      await tester.pumpAndSettle();

      expect(gateway.lastAllowMultiple, isFalse);
      expect(gateway.lastLoadBytes, isFalse);
      expect(gateway.lastAllowedExtensions, <String>['pt']);
      expect(fakeApi.lastUploadedFilename, isNull);
      expect(selected?.name, 'ds.pt');
      expect(selected?.path, '/some/picked/ds.pt');
    });

    testWidgets('cancelling the picker (null result) leaves value unchanged', (
      WidgetTester tester,
    ) async {
      final gateway = _FakeNativeFileDialogGateway(pickFilesResult: null);
      final fakeApi = _FakeApiClient();
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);
      var onChangedCalled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: DatasetPathField(
                value: '',
                format: 'npy',
                onChanged: (_) => onChangedCalled = true,
                onFileSelected: (_) => onChangedCalled = true,
                gateway: gateway,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(ZetaIcons.folder_outline));
      await tester.pumpAndSettle();

      expect(gateway.lastAllowedExtensions, <String>['npy']);
      expect(onChangedCalled, isFalse);
      expect(fakeApi.lastUploadedFilename, isNull);
    });

    testWidgets(
      'a pickFiles failure shows a SnackBar instead of doing nothing',
      (WidgetTester tester) async {
        // Regression test: _browse() used to only wrap the upload call in
        // try/catch, leaving pickFiles() unguarded — a thrown
        // PlatformException from the picker propagated to the zone error
        // handler with no visible feedback at all ("nothing happens").
        final gateway = _FakeNativeFileDialogGateway(
          pickFilesError: StateError('picker failed to open'),
        );
        final fakeApi = _FakeApiClient();
        final container = ProviderContainer(
          overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: DatasetPathField(
                  value: '',
                  format: 'pt',
                  onChanged: (_) {},
                  onFileSelected: (_) {},
                  gateway: gateway,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(ZetaIcons.folder_outline));
        await tester.pumpAndSettle();

        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason:
              'A pickFiles() failure must surface a SnackBar just like an '
              'upload failure does — silently swallowing it is exactly the '
              '"nothing happens" bug.',
        );
        expect(fakeApi.lastUploadedFilename, isNull);
      },
    );

    testWidgets('a selected file without a path shows a SnackBar', (
      WidgetTester tester,
    ) async {
      final gateway = _FakeNativeFileDialogGateway(
        pickFilesResult: <PickedFileData>[
          PickedFileData(name: 'ds.pt', bytes: Uint8List(0)),
        ],
      );
      final fakeApi = _FakeApiClient();
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);
      var onChangedCalled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DatasetPathField(
                value: '',
                format: 'pt',
                onChanged: (_) => onChangedCalled = true,
                onFileSelected: (_) => onChangedCalled = true,
                gateway: gateway,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(ZetaIcons.folder_outline));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(onChangedCalled, isFalse);
    });
  });

  group('DatasetPathField reachability indicator', () {
    testWidgets(
      'checks a client path locally and shows deferred-upload state',
      (WidgetTester tester) async {
        final fakeApi = _FakeApiClient();
        final container = ProviderContainer(
          overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);
        String? checkedPath;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Material(
                child: DatasetPathField(
                  value: '/local/mnist.pt',
                  format: 'pt',
                  pathScope: kClientDatasetPathScope,
                  fileName: 'mnist.pt',
                  onChanged: (_) {},
                  onFileSelected: (_) {},
                  localPathExists: (path) async {
                    checkedPath = path;
                    return false;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(checkedPath, '/local/mnist.pt');
        expect(fakeApi.lastCheckedPath, isNull);
        expect(find.text('mnist.pt uploads on Generate'), findsOneWidget);
        expect(find.byIcon(ZetaIcons.warning_outline), findsOneWidget);
      },
    );

    testWidgets(
      'shows a warning icon when the backend reports the path missing',
      (WidgetTester tester) async {
        final fakeApi = _FakeApiClient(pathExists: false);
        final container = ProviderContainer(
          overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Material(
                child: DatasetPathField(
                  value: '/home/app/data/pipeline_uploads/gone/ds_train.pt',
                  format: 'pt',
                  onChanged: (_) {},
                  onFileSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          fakeApi.lastCheckedPath,
          '/home/app/data/pipeline_uploads/gone/ds_train.pt',
        );
        expect(find.byIcon(ZetaIcons.warning_outline), findsOneWidget);
      },
    );

    testWidgets('shows no warning icon when the backend reports the path '
        'still exists', (WidgetTester tester) async {
      final fakeApi = _FakeApiClient(pathExists: true);
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: DatasetPathField(
                value: '/home/app/data/pipeline_uploads/ok/ds_train.pt',
                format: 'pt',
                onChanged: (_) {},
                onFileSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(ZetaIcons.warning_outline), findsNothing);
    });

    testWidgets('re-checks when the path changes to a different value', (
      WidgetTester tester,
    ) async {
      final fakeApi = _FakeApiClient(pathExists: false);
      final container = ProviderContainer(
        overrides: <Override>[apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: DatasetPathField(
                value: '/data/pipeline_uploads/a/ds.pt',
                format: 'pt',
                onChanged: (_) {},
                onFileSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(ZetaIcons.warning_outline), findsOneWidget);

      fakeApi.pathExists = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: DatasetPathField(
                value: '/data/pipeline_uploads/b/ds.pt',
                format: 'pt',
                onChanged: (_) {},
                onFileSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.lastCheckedPath, '/data/pipeline_uploads/b/ds.pt');
      expect(find.byIcon(ZetaIcons.warning_outline), findsNothing);
    });
  });
}

/// Fake `ApiClient` that skips the real network calls `uploadRawDatasetFile`
/// and `checkDatasetPathExists` would make, so `DatasetPathField`'s tests
/// stay hermetic.
class _FakeApiClient extends app_api.ApiClient {
  _FakeApiClient({this.pathExists = true}) : super(baseUrl: 'http://test');

  final String uploadedPath = '/server/pipeline_uploads/ds.pt';
  String? lastUploadedFilename;

  bool pathExists;
  String? lastCheckedPath;

  @override
  Future<String> uploadRawDatasetFile({
    required String filename,
    required Uint8List bytes,
  }) async {
    lastUploadedFilename = filename;
    return uploadedPath;
  }

  @override
  Future<bool> checkDatasetPathExists(String path) async {
    lastCheckedPath = path;
    return pathExists;
  }
}

/// Hand-written fake mirroring the one in
/// test/services/file_picker_native_file_backend_test.dart — Dart privacy is
/// per-file, so it can't be reused directly and is duplicated here.
class _FakeNativeFileDialogGateway implements NativeFileDialogGateway {
  _FakeNativeFileDialogGateway({this.pickFilesResult, this.pickFilesError});

  final List<PickedFileData>? pickFilesResult;
  final Object? pickFilesError;

  bool? lastAllowMultiple;
  bool? lastLoadBytes;
  List<String>? lastAllowedExtensions;

  @override
  Future<List<PickedFileData>?> pickFiles({
    required bool allowMultiple,
    required List<String> allowedExtensions,
    bool loadBytes = true,
  }) async {
    lastAllowMultiple = allowMultiple;
    lastLoadBytes = loadBytes;
    lastAllowedExtensions = allowedExtensions;
    if (pickFilesError != null) {
      throw pickFilesError!;
    }
    return pickFilesResult;
  }

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) {
    throw UnimplementedError();
  }
}
