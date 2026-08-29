// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ValidationController)
final validationControllerProvider = ValidationControllerProvider._();

final class ValidationControllerProvider
    extends
        $NotifierProvider<ValidationController, AsyncValue<ValidationResult>> {
  ValidationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'validationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$validationControllerHash();

  @$internal
  @override
  ValidationController create() => ValidationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ValidationResult> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ValidationResult>>(value),
    );
  }
}

String _$validationControllerHash() =>
    r'3b0d5d248683ebc18a77d897778bd5bc303d7dbc';

abstract class _$ValidationController
    extends $Notifier<AsyncValue<ValidationResult>> {
  AsyncValue<ValidationResult> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ValidationResult>, AsyncValue<ValidationResult>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ValidationResult>,
                AsyncValue<ValidationResult>
              >,
              AsyncValue<ValidationResult>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
