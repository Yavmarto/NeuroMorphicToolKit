// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'environment_package_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-environment package list notifier.
///
/// Keyed by environment slug so each card gets its own isolated cache.
/// `autoDispose` ensures memory is freed when the card collapses or unmounts.

@ProviderFor(EnvironmentPackageNotifier)
final environmentPackageProvider = EnvironmentPackageNotifierFamily._();

/// Per-environment package list notifier.
///
/// Keyed by environment slug so each card gets its own isolated cache.
/// `autoDispose` ensures memory is freed when the card collapses or unmounts.
final class EnvironmentPackageNotifierProvider
    extends
        $NotifierProvider<EnvironmentPackageNotifier, EnvironmentPackageState> {
  /// Per-environment package list notifier.
  ///
  /// Keyed by environment slug so each card gets its own isolated cache.
  /// `autoDispose` ensures memory is freed when the card collapses or unmounts.
  EnvironmentPackageNotifierProvider._({
    required EnvironmentPackageNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'environmentPackageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$environmentPackageNotifierHash();

  @override
  String toString() {
    return r'environmentPackageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  EnvironmentPackageNotifier create() => EnvironmentPackageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnvironmentPackageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EnvironmentPackageState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EnvironmentPackageNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$environmentPackageNotifierHash() =>
    r'f89e74b1b0b829c48a47c4f769b03c6b27926343';

/// Per-environment package list notifier.
///
/// Keyed by environment slug so each card gets its own isolated cache.
/// `autoDispose` ensures memory is freed when the card collapses or unmounts.

final class EnvironmentPackageNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          EnvironmentPackageNotifier,
          EnvironmentPackageState,
          EnvironmentPackageState,
          EnvironmentPackageState,
          String
        > {
  EnvironmentPackageNotifierFamily._()
    : super(
        retry: null,
        name: r'environmentPackageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-environment package list notifier.
  ///
  /// Keyed by environment slug so each card gets its own isolated cache.
  /// `autoDispose` ensures memory is freed when the card collapses or unmounts.

  EnvironmentPackageNotifierProvider call(String slug) =>
      EnvironmentPackageNotifierProvider._(argument: slug, from: this);

  @override
  String toString() => r'environmentPackageProvider';
}

/// Per-environment package list notifier.
///
/// Keyed by environment slug so each card gets its own isolated cache.
/// `autoDispose` ensures memory is freed when the card collapses or unmounts.

abstract class _$EnvironmentPackageNotifier
    extends $Notifier<EnvironmentPackageState> {
  late final _$args = ref.$arg as String;
  String get slug => _$args;

  EnvironmentPackageState build(String slug);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<EnvironmentPackageState, EnvironmentPackageState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EnvironmentPackageState, EnvironmentPackageState>,
              EnvironmentPackageState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// Per-environment requirements export notifier.
///
/// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
/// open. The mode switch triggers a manual call to [reload].

@ProviderFor(EnvironmentExportNotifier)
final environmentExportProvider = EnvironmentExportNotifierFamily._();

/// Per-environment requirements export notifier.
///
/// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
/// open. The mode switch triggers a manual call to [reload].
final class EnvironmentExportNotifierProvider
    extends
        $AsyncNotifierProvider<
          EnvironmentExportNotifier,
          EnvironmentExportState
        > {
  /// Per-environment requirements export notifier.
  ///
  /// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
  /// open. The mode switch triggers a manual call to [reload].
  EnvironmentExportNotifierProvider._({
    required EnvironmentExportNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'environmentExportProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$environmentExportNotifierHash();

  @override
  String toString() {
    return r'environmentExportProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  EnvironmentExportNotifier create() => EnvironmentExportNotifier();

  @override
  bool operator ==(Object other) {
    return other is EnvironmentExportNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$environmentExportNotifierHash() =>
    r'68502fdb2f21d995a46565af8ad4f06a726fa67d';

/// Per-environment requirements export notifier.
///
/// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
/// open. The mode switch triggers a manual call to [reload].

final class EnvironmentExportNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          EnvironmentExportNotifier,
          AsyncValue<EnvironmentExportState>,
          EnvironmentExportState,
          FutureOr<EnvironmentExportState>,
          String
        > {
  EnvironmentExportNotifierFamily._()
    : super(
        retry: null,
        name: r'environmentExportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-environment requirements export notifier.
  ///
  /// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
  /// open. The mode switch triggers a manual call to [reload].

  EnvironmentExportNotifierProvider call(String slug) =>
      EnvironmentExportNotifierProvider._(argument: slug, from: this);

  @override
  String toString() => r'environmentExportProvider';
}

/// Per-environment requirements export notifier.
///
/// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
/// open. The mode switch triggers a manual call to [reload].

abstract class _$EnvironmentExportNotifier
    extends $AsyncNotifier<EnvironmentExportState> {
  late final _$args = ref.$arg as String;
  String get slug => _$args;

  FutureOr<EnvironmentExportState> build(String slug);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<EnvironmentExportState>, EnvironmentExportState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<EnvironmentExportState>,
                EnvironmentExportState
              >,
              AsyncValue<EnvironmentExportState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
