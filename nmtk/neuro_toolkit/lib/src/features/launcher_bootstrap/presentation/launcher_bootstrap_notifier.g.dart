// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'launcher_bootstrap_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the pre-app bootstrap flow: probing the launcher control API, loading
/// launcher settings, and surfacing the combined result to the widget tree.
///
/// Replaces all [setState] calls in [_LauncherBootstrapHostState] in main.dart.
///
/// `keepAlive: true` because this provider owns the one-time bootstrap sequence
/// and must not reset when the widget temporarily unmounts during the transition
/// from the setup flow to the main app shell.

@ProviderFor(LauncherBootstrapNotifier)
final launcherBootstrapProvider = LauncherBootstrapNotifierProvider._();

/// Drives the pre-app bootstrap flow: probing the launcher control API, loading
/// launcher settings, and surfacing the combined result to the widget tree.
///
/// Replaces all [setState] calls in [_LauncherBootstrapHostState] in main.dart.
///
/// `keepAlive: true` because this provider owns the one-time bootstrap sequence
/// and must not reset when the widget temporarily unmounts during the transition
/// from the setup flow to the main app shell.
final class LauncherBootstrapNotifierProvider extends $AsyncNotifierProvider<
    LauncherBootstrapNotifier, LauncherBootstrapData> {
  /// Drives the pre-app bootstrap flow: probing the launcher control API, loading
  /// launcher settings, and surfacing the combined result to the widget tree.
  ///
  /// Replaces all [setState] calls in [_LauncherBootstrapHostState] in main.dart.
  ///
  /// `keepAlive: true` because this provider owns the one-time bootstrap sequence
  /// and must not reset when the widget temporarily unmounts during the transition
  /// from the setup flow to the main app shell.
  LauncherBootstrapNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'launcherBootstrapProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$launcherBootstrapNotifierHash();

  @$internal
  @override
  LauncherBootstrapNotifier create() => LauncherBootstrapNotifier();
}

String _$launcherBootstrapNotifierHash() =>
    r'72cc029982a9c5ef3390bcc3a5f945812edddb49';

/// Drives the pre-app bootstrap flow: probing the launcher control API, loading
/// launcher settings, and surfacing the combined result to the widget tree.
///
/// Replaces all [setState] calls in [_LauncherBootstrapHostState] in main.dart.
///
/// `keepAlive: true` because this provider owns the one-time bootstrap sequence
/// and must not reset when the widget temporarily unmounts during the transition
/// from the setup flow to the main app shell.

abstract class _$LauncherBootstrapNotifier
    extends $AsyncNotifier<LauncherBootstrapData> {
  FutureOr<LauncherBootstrapData> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref
        as $Ref<AsyncValue<LauncherBootstrapData>, LauncherBootstrapData>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<LauncherBootstrapData>, LauncherBootstrapData>,
        AsyncValue<LauncherBootstrapData>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
