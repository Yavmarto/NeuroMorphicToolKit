/// Configuration for services that are intentionally external to a selected
/// NMTK backend. NeuroStudio's backend is supplied by the root launch context.
class AppConfig {
  /// The one central Neurohub API URL. Unlike [apiBaseUrl], this never
  /// resolves against the user's own private backend — Neurohub is a single
  /// shared service, not something each self-deployed backend runs a copy
  /// of. Empty by default until an operator deploys the central service and
  /// a release pins its URL here.
  static const neurohubApiUrl = String.fromEnvironment(
    'NEUROHUB_API_URL',
    defaultValue: '',
  );
}
