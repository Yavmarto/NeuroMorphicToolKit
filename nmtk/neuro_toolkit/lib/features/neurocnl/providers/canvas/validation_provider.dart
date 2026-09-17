import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';

part 'validation_provider.g.dart';

@riverpod
class ValidationController extends _$ValidationController {
  @override
  AsyncValue<ValidationResult> build() => const AsyncValue.loading();

  Future<void> validate(CanvasGraph graph) async {
    state = const AsyncValue.loading();
    try {
      final result = await ref.read(apiClientProvider).validateGraph(graph);
      if (ref.mounted) {
        state = AsyncValue.data(result);
      }
    } catch (e, stack) {
      if (ref.mounted) {
        state = AsyncValue.error(e, stack);
      }
    }
  }
}

/// Backward-compat alias.
final validationProvider = validationControllerProvider;
