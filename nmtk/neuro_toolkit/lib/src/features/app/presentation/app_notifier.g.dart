// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppNotifier)
final appProvider = AppNotifierProvider._();

final class AppNotifierProvider
    extends $NotifierProvider<AppNotifier, AppState> {
  AppNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appNotifierHash();

  @$internal
  @override
  AppNotifier create() => AppNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppState>(value),
    );
  }
}

String _$appNotifierHash() => r'4c43803518ee1acc29b28406c55c70a83ea2f06e';

abstract class _$AppNotifier extends $Notifier<AppState> {
  AppState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AppState, AppState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AppState, AppState>, AppState, Object?, Object?>;
    element.handleCreate(ref, build);
  }
}
