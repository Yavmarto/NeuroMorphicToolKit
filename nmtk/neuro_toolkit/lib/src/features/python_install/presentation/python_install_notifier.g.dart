// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'python_install_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages the Python installation/detection flow, including:
/// - Homebrew-based installation with streamed output
/// - Python re-detection via the module provider
///
/// This notifier is `autoDispose` so it resets when the setup screen is
/// unmounted, preventing stale install state from persisting between visits.

@ProviderFor(PythonInstallNotifier)
final pythonInstallProvider = PythonInstallNotifierProvider._();

/// Manages the Python installation/detection flow, including:
/// - Homebrew-based installation with streamed output
/// - Python re-detection via the module provider
///
/// This notifier is `autoDispose` so it resets when the setup screen is
/// unmounted, preventing stale install state from persisting between visits.
final class PythonInstallNotifierProvider
    extends $NotifierProvider<PythonInstallNotifier, PythonInstallState> {
  /// Manages the Python installation/detection flow, including:
  /// - Homebrew-based installation with streamed output
  /// - Python re-detection via the module provider
  ///
  /// This notifier is `autoDispose` so it resets when the setup screen is
  /// unmounted, preventing stale install state from persisting between visits.
  PythonInstallNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pythonInstallProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pythonInstallNotifierHash();

  @$internal
  @override
  PythonInstallNotifier create() => PythonInstallNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PythonInstallState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PythonInstallState>(value),
    );
  }
}

String _$pythonInstallNotifierHash() =>
    r'9c6a881e1563e5e73c9f7b92dc5bdfdc63a2d696';

/// Manages the Python installation/detection flow, including:
/// - Homebrew-based installation with streamed output
/// - Python re-detection via the module provider
///
/// This notifier is `autoDispose` so it resets when the setup screen is
/// unmounted, preventing stale install state from persisting between visits.

abstract class _$PythonInstallNotifier extends $Notifier<PythonInstallState> {
  PythonInstallState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PythonInstallState, PythonInstallState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PythonInstallState, PythonInstallState>,
              PythonInstallState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
