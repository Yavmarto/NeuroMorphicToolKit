// neurocnl domain feature package.
//
// Exposes [NeurocnlShell] — the top-level native Flutter screen for the
// CNL Studio, pre-configured to reach suite_api at /api/neurocnl.
//
// API base URL is read from the SUITE_API_URL dart-define at build time:
//   flutter run --dart-define=SUITE_API_URL=http://localhost:9000
//
// Feature flag for conditional navigation in the launcher:
//   const kNeurocnlNativeScreen = bool.fromEnvironment('NATIVE_NEUROCNL', defaultValue: true);
export 'src/neurocnl_shell.dart';
