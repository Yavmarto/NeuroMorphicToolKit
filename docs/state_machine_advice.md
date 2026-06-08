# State Machine Implementation Advice for Riverpod 3

Given your recent migration to Riverpod 3 for the frontend, introducing explicit State Machines is a **highly recommended** architectural enhancement, particularly for complex flows.

## 1. Is it Useful?

**Yes, absolutely.** Currently, many of your state classes (like `WorkspaceState` or `AppState`) are flat data structures (struct-like) with multiple independent fields (e.g., `bool isLoading`, `String? error`, `Data? data`). 

Implementing a State Machine (Finite State Machine - FSM) provides several massive benefits:
- **Eliminates Impossible States:** You can no longer accidentally have `isLoading = true` *and* an error message showing simultaneously. The UI state is strictly deterministic.
- **Exhaustive UI Matching:** Dart 3 combined with Freezed or sealed classes forces the UI to handle *every single state*. If you add a new state, the compiler will error out anywhere in the UI that forgot to handle it.
- **Predictable Transitions:** Logic becomes much easier to debug because state transitions (e.g., `Connecting` -> `Connected` -> `Streaming`) are explicitly modeled.

**Best Candidates for State Machines in NMTK:**
- Hardware connection flows (e.g., connecting to Neurochip/Teensy).
- Multi-step wizards or complex dialogs.
- Simulation execution lifecycles (Idle -> Compiling -> Running -> Finished/Error).

---

## 2. How Should it be Implemented?

With Riverpod 3 and Dart 3, you should combine **Riverpod Notifiers** (for the state container and transitions) with **Dart 3 Sealed Classes** or **Freezed Unions** (for the states). Since your project already heavily uses `@freezed`, Freezed unions are the natural choice.

### Step A: Define the States (The Model)
Use a Freezed union to define mutually exclusive states.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'hardware_connection_state.freezed.dart';

@freezed
sealed class HardwareConnectionState with _$HardwareConnectionState {
  const factory HardwareConnectionState.disconnected() = _Disconnected;
  const factory HardwareConnectionState.connecting() = _Connecting;
  const factory HardwareConnectionState.connected(String port) = _Connected;
  const factory HardwareConnectionState.error(String message) = _Error;
}
```

### Step B: Define the State Machine (The Notifier)
Use Riverpod's code-generated `@riverpod` Notifier. The methods on the Notifier act as the **Events** that trigger transitions.

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'hardware_connection_state.dart';

part 'hardware_connection_controller.g.dart';

@riverpod
class HardwareConnectionController extends _$HardwareConnectionController {
  @override
  HardwareConnectionState build() {
    return const HardwareConnectionState.disconnected();
  }

  // Event: connect()
  Future<void> connect(String port) async {
    // Only transition if we are currently disconnected or errored
    if (state is! _Disconnected && state is! _Error) return;

    state = const HardwareConnectionState.connecting();
    try {
      // Perform connection logic...
      await Future.delayed(const Duration(seconds: 2));
      state = HardwareConnectionState.connected(port);
    } catch (e) {
      state = HardwareConnectionState.error(e.toString());
    }
  }

  // Event: disconnect()
  void disconnect() {
    state = const HardwareConnectionState.disconnected();
  }
}
```

### Step C: The UI (The Consumer)
In your widget, use `ref.watch` and a Dart 3 `switch` statement. The compiler will enforce exhaustive matching.

```dart
class ConnectionStatusWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hardwareConnectionControllerProvider);

    // Dart 3 switch expression guarantees all states are handled!
    return switch (state) {
      _Disconnected() => const Text('Ready to connect'),
      _Connecting() => const CircularProgressIndicator(),
      _Connected(:final port) => Text('Connected to $port'),
      _Error(:final message) => Text('Error: $message', style: TextStyle(color: Colors.red)),
    };
  }
}
```

---

## 3. Where Should it be Implemented?

Following standard feature-first architecture (which seems to align with the `nmtk/neuro_toolkit/lib/src/features/` structure):

1. **State Definition (`.dart` / `.freezed.dart`)**:
   Place this in the `domain` or `presentation` folder of the specific feature.
   *Example: `lib/src/features/deployment/domain/deployment_status_state.dart`*

2. **The Notifier/State Machine (`.dart` / `.g.dart`)**:
   Place this in the `presentation` folder of the specific feature, as it acts as the Controller bridging the UI and the domain/application layers.
   *Example: `lib/src/features/deployment/presentation/deployment_controller.dart`*

3. **Avoid Globals / `nmtk_ui_core`**:
   Keep state machines out of `nmtk_ui_core`. As per `nmtk-flutter-review` guidelines, `nmtk_ui_core` should remain purely presentational and agnostic to Riverpod or business logic state machines. State machines belong in the specific feature modules (`neurocnl`, `Neurochip`, etc.) or the central `neuro_toolkit` app shell where the specific business logic resides.
