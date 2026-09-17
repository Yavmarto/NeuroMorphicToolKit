/// Floor for the visualization/result panels, and how much of the viewport the
/// step header, padding and page scroll take before they get their share.
const double kMinPanelHeight = 480;
const double kPanelChromeAllowance = 260;

/// The result surface holds stacked metric tiles and a per-class chart: it
/// flexes, but not below a legible width or past a comfortable measure.
const double kSurfaceMinWidth = 320;
const double kSurfaceMaxWidth = 520;

/// Akida deploy results: the visualization panel plus the sample/benchmark
/// surface. Lives in the Review step — the Deploy step keeps only the setup and
/// the run controls ([AkidaExecutionControls]).
