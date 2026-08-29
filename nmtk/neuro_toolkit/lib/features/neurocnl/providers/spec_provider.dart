import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';

part 'spec_provider.g.dart';

/// Read/write facade over the CNL text held by [canonicalDocControllerProvider]
/// — content lives solely there now, this is not an independent copy. Kept
/// as a controller (rather than a plain derived `Provider`) because many
/// call sites mutate through `specTextProvider.notifier`; those methods just
/// forward into the one real owner.
@riverpod
class SpecTextController extends _$SpecTextController {
  @override
  String build() {
    final pending = ref.watch(pendingCnlEditProvider);
    if (pending != null) return pending;
    return ref.watch(
      canonicalDocControllerProvider.select((doc) => doc.value?.cnlText ?? ''),
    );
  }

  /// Live-typing update: instant optimistic echo, debounced backend commit.
  /// The optimistic echo (readable via [specTextProvider] immediately after
  /// this call) is synchronous; the returned future resolves once the
  /// debounced backend commit actually lands.
  Future<void> update(String text) {
    return ref.read(canonicalDocControllerProvider.notifier).editCnlText(text);
  }

  /// Immediate (undebounced) replace — used by template/import/NIR-derived
  /// loads that must land right away, not on a typing debounce.
  Future<void> set(String text) {
    ref.read(pendingCnlEditProvider.notifier).state = text;
    return ref
        .read(canonicalDocControllerProvider.notifier)
        .updateFromCnl(text);
  }

  /// Commit any pending debounced edit immediately.
  Future<void> flush() {
    return ref
        .read(canonicalDocControllerProvider.notifier)
        .flushPendingCnlEdit();
  }
}

/// Backward-compat alias.
final specTextProvider = specTextControllerProvider;

/// Backward-compat alias — previously a narrow selector over the workspace
/// file's raw `content` field; now just mirrors [specTextProvider] since
/// content has one owner.
final activeWorkspaceSpecProvider = Provider<String>(
  (ref) => ref.watch(specTextProvider),
);
