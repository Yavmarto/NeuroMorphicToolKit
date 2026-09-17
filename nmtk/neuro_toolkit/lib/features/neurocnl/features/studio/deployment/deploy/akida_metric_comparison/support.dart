library;

/// Tile width chosen so two fit side by side in the result surface at its
/// minimum width, instead of one 252px tile per row.
const double kMetricTileWidth = 168;

/// How far below baseline still counts as a clean conversion, in percentage
/// points. Beyond this the verdict switches from success to a caution tone.
const double kAccuracyTolerancePp = 1;

/// The one sentence this whole step exists to produce.
///
/// Everything below it is the evidence. Previously the reader had to hold two
/// numbers in their head across a scroll and subtract, and the delta that
/// answered the question was rendered last and smallest.
