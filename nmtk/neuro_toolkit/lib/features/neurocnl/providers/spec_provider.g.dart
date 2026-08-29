// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spec_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Read/write facade over the CNL text held by [canonicalDocControllerProvider]
/// — content lives solely there now, this is not an independent copy. Kept
/// as a controller (rather than a plain derived `Provider`) because many
/// call sites mutate through `specTextProvider.notifier`; those methods just
/// forward into the one real owner.

@ProviderFor(SpecTextController)
final specTextControllerProvider = SpecTextControllerProvider._();

/// Read/write facade over the CNL text held by [canonicalDocControllerProvider]
/// — content lives solely there now, this is not an independent copy. Kept
/// as a controller (rather than a plain derived `Provider`) because many
/// call sites mutate through `specTextProvider.notifier`; those methods just
/// forward into the one real owner.
final class SpecTextControllerProvider
    extends $NotifierProvider<SpecTextController, String> {
  /// Read/write facade over the CNL text held by [canonicalDocControllerProvider]
  /// — content lives solely there now, this is not an independent copy. Kept
  /// as a controller (rather than a plain derived `Provider`) because many
  /// call sites mutate through `specTextProvider.notifier`; those methods just
  /// forward into the one real owner.
  SpecTextControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'specTextControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$specTextControllerHash();

  @$internal
  @override
  SpecTextController create() => SpecTextController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$specTextControllerHash() =>
    r'284a08af2cab4928c788111f9bd78f441f402e11';

/// Read/write facade over the CNL text held by [canonicalDocControllerProvider]
/// — content lives solely there now, this is not an independent copy. Kept
/// as a controller (rather than a plain derived `Provider`) because many
/// call sites mutate through `specTextProvider.notifier`; those methods just
/// forward into the one real owner.

abstract class _$SpecTextController extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
