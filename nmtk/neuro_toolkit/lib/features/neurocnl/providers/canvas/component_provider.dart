import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';

final categoryComponentsProvider =
    FutureProvider.family<List<ComponentBlock>, String>((ref, category) async {
      final apiClient = ref.watch(apiClientProvider);
      return apiClient.fetchComponents(category: category);
    });

final componentsProvider = FutureProvider<List<ComponentBlock>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.fetchComponents();
});
