import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/dataset_generation_preparer.dart';
import 'package:neuro_toolkit/features/neurocnl/services/notebook_generate_service.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/nir_import_state.dart';

const _inspectResult = NirInspectResult(
  fileName: 'model.nir',
  fileSizeBytes: 1,
  root: NirHdf5Group(name: '/', attrs: {}, children: []),
);

void main() {
  test('prefers canonical NIR-derived spec when available', () {
    final spec = NotebookGenerateService.preferredSpecForNotebook(
      specText: 'stale editor spec',
      canonicalSpecText: 'nir derived spec',
    );

    expect(spec, 'nir derived spec');
  });

  test('falls back to editor spec when canonical spec is empty', () {
    final spec = NotebookGenerateService.preferredSpecForNotebook(
      specText: 'editor spec',
      canonicalSpecText: '   ',
    );

    expect(spec, 'editor spec');
  });

  test(
    'uses retained file-backed NIR import id after inspector state refresh',
    () {
      final importId = NotebookGenerateService.importIdForNotebook(
        nirImportState: const NirImportState.idle(),
        retainedFileBackedImportId: 'cnn-sinabs-import',
      );

      expect(importId, 'cnn-sinabs-import');
    },
  );

  test('current loaded NIR import id wins over retained fallback', () {
    final importId = NotebookGenerateService.importIdForNotebook(
      nirImportState: const NirImportState.loaded(
        result: _inspectResult,
        source: NirSource.file,
        importId: 'current-import',
      ),
      retainedFileBackedImportId: 'older-retained-import',
    );

    expect(importId, 'current-import');
  });

  test('builds an isolated reset Jupyter workspace at the notebook folder', () {
    final url = NotebookGenerateService.passiveJupyterFolderUrl(
      targetUrl: 'http://backend.example:8008/lab/tree/demo/notebooks/',
      workspaceFolder: 'demo/notebooks',
      cacheBust: 1234,
    );

    final uri = Uri.parse(url);
    expect(uri.path, '/lab/workspaces/nmtk-demo/tree/demo/notebooks/');
    expect(uri.queryParameters, containsPair('reset', ''));
    expect(uri.queryParameters, containsPair('ts', '1234'));
    expect(uri.path, isNot(contains('.ipynb')));
  });

  test('preserves a reverse-proxy prefix in passive Jupyter URLs', () {
    final url = NotebookGenerateService.passiveJupyterFolderUrl(
      targetUrl: 'https://suite.example/tools/jupyter/lab/tree/demo/notebooks/',
      workspaceFolder: 'demo/notebooks',
      cacheBust: 9,
    );

    expect(
      Uri.parse(url).path,
      '/tools/jupyter/lab/workspaces/nmtk-demo/tree/demo/notebooks/',
    );
  });

  test('resolveJupyterUrl trusts a backend-supplied jupyterUrl', () {
    final url = NotebookGenerateService.resolveJupyterUrl(
      jupyterUrl: 'https://suite.example/tools/jupyter/lab/tree/demo/',
      workspaceFolder: 'demo',
      baseUrl: 'http://192.168.2.90:9000',
    );

    expect(url, 'https://suite.example/tools/jupyter/lab/tree/demo/');
  });

  test(
    'resolveJupyterUrl derives from baseUrl when backend left jupyterUrl empty',
    () {
      final url = NotebookGenerateService.resolveJupyterUrl(
        jupyterUrl: '',
        workspaceFolder: 'demo',
        baseUrl: 'http://192.168.2.90:9000',
      );

      expect(url, 'http://192.168.2.90:8008/lab/tree/demo/');
    },
  );

  test('upload and backend failures route to System Health', () {
    expect(
      NotebookGenerateService.shouldOfferSystemHealth(
        const DatasetPreparationException('upload failed'),
      ),
      isTrue,
    );
    expect(
      NotebookGenerateService.shouldOfferSystemHealth(
        const ApiException(503, 'Jupyter unavailable'),
      ),
      isTrue,
    );
    expect(NotebookGenerateService.systemHealthUri, 'nmtk://system-health');
  });
}
