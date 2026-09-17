import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dismissed_job_provider.g.dart';

/// When set, hides the active jobs bar for this job id until a new job starts.
@riverpod
class DismissedActiveJobBarId extends _$DismissedActiveJobBarId {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}
