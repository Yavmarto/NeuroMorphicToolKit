// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canonical_doc_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(CanonicalDocController)
final canonicalDocControllerProvider = CanonicalDocControllerProvider._();

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
final class CanonicalDocControllerProvider
    extends
        $NotifierProvider<
          CanonicalDocController,
          AsyncValue<CanonicalEditorDocument?>
        > {
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
  CanonicalDocControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canonicalDocControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canonicalDocControllerHash();

  @$internal
  @override
  CanonicalDocController create() => CanonicalDocController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<CanonicalEditorDocument?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AsyncValue<CanonicalEditorDocument?>>(value),
    );
  }
}

String _$canonicalDocControllerHash() =>
    r'7d90d81c0eb58e1c1feddae225fd80176c49c1ee';

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

abstract class _$CanonicalDocController
    extends $Notifier<AsyncValue<CanonicalEditorDocument?>> {
  AsyncValue<CanonicalEditorDocument?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<CanonicalEditorDocument?>,
              AsyncValue<CanonicalEditorDocument?>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<CanonicalEditorDocument?>,
                AsyncValue<CanonicalEditorDocument?>
              >,
              AsyncValue<CanonicalEditorDocument?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
