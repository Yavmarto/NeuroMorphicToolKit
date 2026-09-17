import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'target_availability_provider.g.dart';

@riverpod
Future<Map<String, bool>> targetAvailability(Ref ref) async {
  final api = ref.read(apiClientProvider);
  return api.getTargetAvailability();
}
