// ServerConfigService.mergeJsonString — serialized read-modify-write.
//
// Bug this guards against: WorkspaceController._doPersist and
// _StudioWorkspaceFileIo._scheduleCanvasAutosave used to each do their own
// unsynchronized read-then-write of the same local-storage key, each only
// owning one top-level field ('workspace' vs 'canvas') and preserving the
// other via a stale re-read. Two overlapping writes could interleave so
// whichever finished last silently reverted the other's just-written field.
//
// mergeJsonString serializes callers per key so this can't happen: each
// caller's `merge` function only ever sees either the initial empty object
// or the fully-applied result of every merge queued before it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  test(
    'two concurrent merges to the same key both survive, not last-write-wins',
    () async {
      const key = 'test_merge_key';

      // Fired back-to-back, NOT awaited individually first — this is the
      // exact overlap shape of the original bug: two independent writers,
      // each owning a different field, racing on the same key.
      final workspaceWrite = ServerConfigService.mergeJsonString(key, (
        current,
      ) {
        return {...current, 'workspace': 'workspace-value'};
      });
      final canvasWrite = ServerConfigService.mergeJsonString(key, (current) {
        return {...current, 'canvas': 'canvas-value'};
      });

      await Future.wait([workspaceWrite, canvasWrite]);

      final stored = jsonDecode(ServerConfigService.getString(key)!) as Map;
      expect(
        stored['workspace'],
        'workspace-value',
        reason:
            'The workspace-owned field must survive even though the canvas '
            'write was queued concurrently.',
      );
      expect(
        stored['canvas'],
        'canvas-value',
        reason:
            'The canvas-owned field must survive even though the workspace '
            'write was queued concurrently.',
      );
    },
  );

  test('a caller that only reads a stale snapshot cannot revert a field it '
      "doesn't own", () async {
    const key = 'test_merge_key_2';

    await ServerConfigService.mergeJsonString(
      key,
      (current) => {...current, 'canvas': 'first-canvas-value'},
    );

    // Ten rapid workspace-only writes, none of which ever touch 'canvas'.
    for (var i = 0; i < 10; i++) {
      await ServerConfigService.mergeJsonString(
        key,
        (current) => {...current, 'workspace': 'workspace-$i'},
      );
    }

    final stored = jsonDecode(ServerConfigService.getString(key)!) as Map;
    expect(stored['canvas'], 'first-canvas-value');
    expect(stored['workspace'], 'workspace-9');
  });

  test('a failing merge does not wedge later merges to the same key', () async {
    const key = 'test_merge_key_3';

    await expectLater(
      ServerConfigService.mergeJsonString(key, (current) {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );

    await ServerConfigService.mergeJsonString(
      key,
      (current) => {...current, 'ok': true},
    );

    final stored = jsonDecode(ServerConfigService.getString(key)!) as Map;
    expect(stored['ok'], isTrue);
  });
}
