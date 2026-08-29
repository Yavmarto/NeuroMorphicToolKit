import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/imported_cnl_spec.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cnl_import_provider.g.dart';

@riverpod
class ImportedCnlSpecController extends _$ImportedCnlSpecController {
  @override
  ImportedCnlSpec? build() => null;

  void setState(ImportedCnlSpec? spec) => state = spec;
}

final importedCnlSpecProvider = importedCnlSpecControllerProvider;

final hasImportedCnlSpecProvider = Provider<bool>((ref) {
  return ref.watch(importedCnlSpecProvider) != null;
});
