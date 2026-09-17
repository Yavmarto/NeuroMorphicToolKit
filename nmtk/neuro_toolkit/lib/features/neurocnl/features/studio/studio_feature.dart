/// NeuroStudio's internal composition entry point.
///
/// The shell adapter is the only package-level entry point.  Routes and
/// feature-local callers import this library instead of reaching into the
/// legacy screen tree directly.
library;

export 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart' show StudioScreen;
