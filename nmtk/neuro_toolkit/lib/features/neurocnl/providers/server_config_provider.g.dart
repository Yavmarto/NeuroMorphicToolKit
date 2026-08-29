// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_config_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages readiness for the connection selected by the root launcher.

@ProviderFor(ServerConfigController)
final serverConfigControllerProvider = ServerConfigControllerProvider._();

/// Manages readiness for the connection selected by the root launcher.
final class ServerConfigControllerProvider
    extends $NotifierProvider<ServerConfigController, ServerConfigState> {
  /// Manages readiness for the connection selected by the root launcher.
  ServerConfigControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverConfigControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverConfigControllerHash();

  @$internal
  @override
  ServerConfigController create() => ServerConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerConfigState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerConfigState>(value),
    );
  }
}

String _$serverConfigControllerHash() =>
    r'abe691f6cfb14da8fcdd840aeb826e75a90ec704';

/// Manages readiness for the connection selected by the root launcher.

abstract class _$ServerConfigController extends $Notifier<ServerConfigState> {
  ServerConfigState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ServerConfigState, ServerConfigState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ServerConfigState, ServerConfigState>,
              ServerConfigState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
