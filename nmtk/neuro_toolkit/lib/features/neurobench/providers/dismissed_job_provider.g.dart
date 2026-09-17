// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dismissed_job_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// When set, hides the active jobs bar for this job id until a new job starts.

@ProviderFor(DismissedActiveJobBarId)
final dismissedActiveJobBarIdProvider = DismissedActiveJobBarIdProvider._();

/// When set, hides the active jobs bar for this job id until a new job starts.
final class DismissedActiveJobBarIdProvider
    extends $NotifierProvider<DismissedActiveJobBarId, String?> {
  /// When set, hides the active jobs bar for this job id until a new job starts.
  DismissedActiveJobBarIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dismissedActiveJobBarIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dismissedActiveJobBarIdHash();

  @$internal
  @override
  DismissedActiveJobBarId create() => DismissedActiveJobBarId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$dismissedActiveJobBarIdHash() =>
    r'e166fad7eb4604c66c866fb17d614e70e361651b';

/// When set, hides the active jobs bar for this job id until a new job starts.

abstract class _$DismissedActiveJobBarId extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
