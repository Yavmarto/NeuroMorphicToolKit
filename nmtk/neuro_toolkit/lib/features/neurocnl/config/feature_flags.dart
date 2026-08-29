/// Feature flags for neurocnl Studio.
///
/// Flags default to false and are enabled via environment variables
/// or runtime configuration. This allows safe rollback of new features.
class FeatureFlags {
  FeatureFlags._();

  /// Whether the training inspector panel is visible in Studio.
  /// Set NEUROCNL_TRAINING_PANEL_ENABLED=1 to enable.
  static bool get trainingPanelEnabled => const bool.fromEnvironment(
    'NEUROCNL_TRAINING_PANEL_ENABLED',
    defaultValue: false,
  );
}
