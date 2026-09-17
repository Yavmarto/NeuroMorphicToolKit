// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'target_availability_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(targetAvailability)
final targetAvailabilityProvider = TargetAvailabilityProvider._();

final class TargetAvailabilityProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, bool>>,
          Map<String, bool>,
          FutureOr<Map<String, bool>>
        >
    with
        $FutureModifier<Map<String, bool>>,
        $FutureProvider<Map<String, bool>> {
  TargetAvailabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'targetAvailabilityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$targetAvailabilityHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, bool>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, bool>> create(Ref ref) {
    return targetAvailability(ref);
  }
}

String _$targetAvailabilityHash() =>
    r'2f18a6daa8aed2480a5c5815dfeeeb2d6e922580';
