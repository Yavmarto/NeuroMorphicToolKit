import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

part 'canonical_doc_provider.g.dart';

/// Optimistic local echo of in-progress CNL typing. Set by
/// [CanonicalDocController.editCnlText], cleared once the debounced backend
/// round-trip that text triggered has resolved (or been superseded by a
/// newer edit). Not persisted, not a second source of truth — purely a
/// transient overlay so the editor renders keystrokes instantly instead of
/// lagging behind the parse round-trip. Consumers that want "the current CNL
/// text, including any not-yet-committed typing" (e.g. [specTextProvider])
/// read this first and fall back to the committed [CanonicalEditorDocument].
class PendingCnlEditNotifier extends Notifier<String?> {
  @override
  String? build() => null;
}

final pendingCnlEditProvider =
    NotifierProvider<PendingCnlEditNotifier, String?>(
      PendingCnlEditNotifier.new,
    );

/// The single source of truth for the studio's network state.
///
/// All three views (CNL editor, Canvas, NIR inspector) are derived from the
/// [CanonicalEditorDocument] held here. Mutations go through one of the three
/// [updateFrom*] methods — each makes one backend call and atomically replaces
/// the document, causing all views to rebuild reactively.
///
/// State shape:
///   AsyncData(null)  — nothing loaded yet
///   AsyncLoading()   — a mutation is in flight
///   AsyncData(doc)   — a fully resolved document
///   AsyncError(...)  — last mutation failed; previous doc is preserved
///
/// The "previous doc is preserved" guarantee depends on every in-flight marker
/// being `copyWithPrevious(state)` rather than a bare `const AsyncLoading()`.
/// A bare one carries no value, and `AsyncError.copyWithPrevious` forwards that
/// null through — so a single failed mutation used to leave `.value == null`
/// permanently, which blanked the CNL editor (`spec_provider.dart` reads
/// `doc.value?.cnlText ?? ''`) and made codegen report "No architecture to
/// generate from". Use [_loadingPreservingDocument]; do not reintroduce a bare
/// `AsyncLoading()` here.
// keepAlive: true is load-bearing, not a performance tweak. This controller
// now owns a live debounce Timer (editCnlText) — if it were autoDispose, a
// momentary drop to zero listeners (e.g. the CNL editor widget unmounting
// mid-debounce) tears the notifier down, which cancels the timer in
// ref.onDispose and silently discards the pending edit. The previous
// reconciler (studio_sync_notifier.dart) needed the same guarantee and was
// keepAlive for the same reason.
@Riverpod(keepAlive: true)
class CanonicalDocController extends _$CanonicalDocController {
  /// Monotonic counter — the only mechanism used to discard a stale
  /// in-flight mutation whose response arrives after a newer one already
  /// won. Replaces the old boolean-flag / last-synced-hash reconciliation
  /// that used to live across canvas_provider.dart and studio_sync_notifier.dart.
  int _generation = 0;

  Timer? _cnlEditDebounce;

  /// In-flight marker that keeps the currently-resolved document readable.
  /// See the "State shape" note on this class for why a bare `AsyncLoading()`
  /// is a bug here rather than a style choice.
  ///
  /// `copyWithPrevious` is `@internal` to riverpod: there is no public API
  /// that lets a hand-rolled `Notifier<AsyncValue<T>>` (as opposed to an
  /// `AsyncNotifier`, which does not fit this class's multi-method mutation
  /// shape) attach a previous value to a fresh `AsyncLoading`/`AsyncError`.
  /// The suppression below is deliberate, not an oversight.
  AsyncValue<CanonicalEditorDocument?> get _loadingPreservingDocument =>
      // ignore: invalid_use_of_internal_member
      const AsyncLoading<CanonicalEditorDocument?>().copyWithPrevious(state);

  @override
  AsyncValue<CanonicalEditorDocument?> build() {
    ref.onDispose(() {
      _cnlEditDebounce?.cancel();
    });
    // React to active file canonical document changes (e.g. a file switch).
    // Guards against the state it's ALREADY at, not just against the
    // previous workspace value — without this, _publishDocument's own
    // `state = AsyncData(document)` plus its immediately-following
    // `setActiveFileCanonicalDocument(document)` call echo back through this
    // exact listener (previous workspace value != document, so the naive
    // `identical(previous, next)` check doesn't catch it) and redundantly
    // re-notify every downstream listener (e.g. canvas_provider.dart's own
    // mirror) a second time for the same document.
    ref.listen<CanonicalEditorDocument?>(
      workspaceProvider.select(
        (workspace) => workspace.activeFile?.canonicalDocument,
      ),
      (previous, next) {
        if (identical(next, state.value)) return;
        state = AsyncData(next);
      },
    );

    final initialDocument = ref
        .read(workspaceProvider)
        .activeFile
        ?.canonicalDocument;
    if (initialDocument != null) {
      return AsyncData(initialDocument);
    }
    return const AsyncData(null);
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  CanonicalEditorDocument? get doc => state.value;
  String get cnlText => doc?.cnlText ?? '';
  CanvasProjection? get canvas => doc?.canvas;

  void _publishDocument(CanonicalEditorDocument? document) {
    state = AsyncData(document);
    ref
        .read(workspaceControllerProvider.notifier)
        .setActiveFileCanonicalDocument(document);
    if (document != null) {
      ref
          .read(pipelineControllerProvider.notifier)
          .runParseAndValidate(document.cnlText);
    }
  }

  bool _matchesActiveDocument(String? fileId, int? revision) {
    if (fileId == null || revision == null) return true;
    final activeFile = ref.read(workspaceProvider).activeFile;
    return activeFile?.id == fileId && activeFile?.revision == revision;
  }

  /// Merge `#`-prefixed comment lines from [previousCnl] that the backend
  /// dropped while regenerating [generatedCnl] from canvas structure. The
  /// backend's canvas→CNL generator does not round-trip free-standing
  /// comments, so the frontend re-attaches any that went missing.
  String _mergePreservedComments(String previousCnl, String generatedCnl) {
    final preservedComments = previousCnl
        .split('\n')
        .where((line) => line.trimLeft().startsWith('#'))
        .toList();
    if (preservedComments.isEmpty) return generatedCnl;
    final generatedLines = generatedCnl.split('\n');
    final commentsToAdd = preservedComments
        .where((c) => !generatedLines.contains(c))
        .toList();
    if (commentsToAdd.isEmpty) return generatedCnl;
    return '${commentsToAdd.join('\n')}\n\n$generatedCnl';
  }

  // ── Mutation: CNL → doc ───────────────────────────────────────────────────

  /// Drops the optimistic echo in [pendingCnlEditProvider] once this commit is
  /// no longer the one that will resolve it. Only clears an echo that is still
  /// *ours* — a newer mutation may already own it.
  ///
  /// Load-bearing: `spec_provider.dart` returns `pending` whenever it is
  /// non-null, short-circuiting the canonical-document read entirely. An echo
  /// left behind by a superseded or wrong-file commit therefore pins the CNL
  /// panel to stale text and it stops tracking the document for good.
  ///
  /// Deliberately NOT called on the parse-error path: there the text is the
  /// user's unparseable draft, and it has to stay in the editor for them to fix.
  void _releaseOptimisticEcho(String cnl) {
    if (!ref.mounted) return;
    if (ref.read(pendingCnlEditProvider) != cnl) return;
    ref.read(pendingCnlEditProvider.notifier).state = null;
  }

  /// Immediate, undebounced CNL→doc update. Callers that want live-typing
  /// debounce should use [editCnlText] instead.
  Future<void> updateFromCnl(String cnl) async {
    if (cnl.isEmpty) {
      _publishDocument(null);
      ref.read(pendingCnlEditProvider.notifier).state = null;
      return;
    }
    final myGen = ++_generation;
    final activeFile = ref.read(workspaceProvider).activeFile;
    final runFileId = activeFile?.id;
    final runRevision = activeFile?.revision;
    state = _loadingPreservingDocument;
    try {
      final response = await ref.read(apiClientProvider).parseCnlCanonical(cnl);
      if (!ref.mounted || myGen != _generation) {
        _releaseOptimisticEcho(cnl);
        return;
      }
      if (!_matchesActiveDocument(runFileId, runRevision)) {
        _releaseOptimisticEcho(cnl);
        return;
      }
      _publishDocument(response.document);
      _releaseOptimisticEcho(cnl);
    } catch (e, st) {
      if (myGen != _generation) return;
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      debugPrint('CanonicalDocController.updateFromCnl error: $e');
      unawaited(
        ref.read(pipelineControllerProvider.notifier).runParseAndValidate(cnl),
      );
      state = AsyncError<CanonicalEditorDocument?>(
        e,
        st,
      ).copyWithPrevious(state); // ignore: invalid_use_of_internal_member
    }
  }

  /// Live-typing entry point for the CNL editor widget. Keeps an optimistic
  /// local echo in [pendingCnlEditProvider] so keystrokes render instantly,
  /// then debounces the real backend round-trip. The returned future
  /// resolves once that debounced commit settles — callers that just want
  /// the instant echo (the normal UI path) can ignore it.
  Future<void> editCnlText(
    String text, {
    Duration debounce = const Duration(milliseconds: 400),
  }) {
    ref.read(pendingCnlEditProvider.notifier).state = text;
    _cnlEditDebounce?.cancel();
    final completer = Completer<void>();
    _cnlEditDebounce = Timer(debounce, () {
      _commitCnlEdit(
        text,
      ).then(completer.complete, onError: completer.completeError);
    });
    return completer.future;
  }

  Future<void> _commitCnlEdit(String text) async {
    if (!ref.mounted) return;
    await updateFromCnl(text);
  }

  /// Flush any pending debounced CNL edit immediately — used when the user
  /// switches away from the CNL panel mid-type so keystrokes aren't lost.
  Future<void> flushPendingCnlEdit() {
    final pending = ref.read(pendingCnlEditProvider);
    _cnlEditDebounce?.cancel();
    if (pending == null) return Future.value();
    return _commitCnlEdit(pending);
  }

  // ── Mutation: Canvas → doc ────────────────────────────────────────────────

  Future<void> updateFromCanvas(CanvasGraph graph) async {
    if (graph.nodes.isEmpty) return;
    final myGen = ++_generation;
    _cnlEditDebounce?.cancel();
    ref.read(pendingCnlEditProvider.notifier).state = null;
    final previousCnl = state.value?.cnlText ?? '';
    final activeFile = ref.read(workspaceProvider).activeFile;
    final runFileId = activeFile?.id;
    final runRevision = activeFile?.revision;
    state = _loadingPreservingDocument;
    try {
      final response = await ref
          .read(apiClientProvider)
          .canvasToCanonical(graph);
      if (!ref.mounted || myGen != _generation) return;
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      final doc = response.document;
      final mergedCnl = _mergePreservedComments(previousCnl, doc.cnlText);
      _publishDocument(
        mergedCnl == doc.cnlText
            ? doc
            : CanonicalEditorDocument(
                irJson: doc.irJson,
                cnlText: mergedCnl,
                fidelityAnnotations: doc.fidelityAnnotations,
                canvas: doc.canvas,
              ),
      );
    } catch (e, st) {
      if (myGen != _generation) return;
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      debugPrint('CanonicalDocController.updateFromCanvas error: $e');
      state = AsyncError<CanonicalEditorDocument?>(
        e,
        st,
      ).copyWithPrevious(state); // ignore: invalid_use_of_internal_member
    }
  }

  // ── Mutation: NIR file → doc ──────────────────────────────────────────────

  Future<void> updateFromNirFile(Uint8List nirBytes) async {
    final myGen = ++_generation;
    _cnlEditDebounce?.cancel();
    ref.read(pendingCnlEditProvider.notifier).state = null;
    final activeFile = ref.read(workspaceProvider).activeFile;
    final runFileId = activeFile?.id;
    final runRevision = activeFile?.revision;
    state = _loadingPreservingDocument;
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.nirBytesToCanonical(nirBytes);
      if (!ref.mounted || myGen != _generation) return;
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      _publishDocument(response.document);
    } catch (e, st) {
      if (myGen != _generation) return;
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      debugPrint('CanonicalDocController.updateFromNirFile error: $e');
      if (!ref.mounted) return;
      state = AsyncError<CanonicalEditorDocument?>(
        e,
        st,
      ).copyWithPrevious(state); // ignore: invalid_use_of_internal_member
    }
  }

  // ── Direct set (workspace load, templates) ────────────────────────────────

  void setDocument(CanonicalEditorDocument doc) {
    ++_generation;
    _cnlEditDebounce?.cancel();
    ref.read(pendingCnlEditProvider.notifier).state = null;
    _publishDocument(doc);
  }

  void clear() {
    ++_generation;
    _cnlEditDebounce?.cancel();
    ref.read(pendingCnlEditProvider.notifier).state = null;
    _publishDocument(null);
  }
}

/// Backward-compat alias.
final canonicalDocProvider = canonicalDocControllerProvider;
