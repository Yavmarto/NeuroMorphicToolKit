import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';

void main() {
  testWidgets('deferred clear waits until widget lifecycle work is finished', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(
      trainingModeProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final notifier = container.read(trainingModeProvider.notifier);
    notifier.setRates(const {'node-1': 0.5});
    notifier.clearDeferred();

    expect(container.read(trainingModeProvider), isNotNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(trainingModeProvider), isNull);
  });
}
