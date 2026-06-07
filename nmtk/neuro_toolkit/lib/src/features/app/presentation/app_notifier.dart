import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/src/features/app/domain/app_state.dart';

part 'app_notifier.g.dart';

@Riverpod(keepAlive: true)
class AppNotifier extends _$AppNotifier {
  @override
  AppState build() {
    return const AppState();
  }

  void toggleDeveloperMode() {
    state = state.copyWith(developerMode: !state.developerMode);
  }
}
