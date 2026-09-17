// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'neurocnl Studio';

  @override
  String get templates => 'Templates';

  @override
  String get runSimulation => 'Run compiled model';

  @override
  String get running => 'Running…';

  @override
  String get export => 'Export';

  @override
  String get duration => 'Duration';

  @override
  String get cnlEditor => 'CNL Editor';

  @override
  String get sentences => 'sentences';

  @override
  String get lines => 'lines';

  @override
  String get parsedSpecs => 'Parsed Specs';

  @override
  String get validation => 'Validation';

  @override
  String get network => 'Network';

  @override
  String get simulation => 'Preview';

  @override
  String get parameters => 'Parameters';

  @override
  String get parse => 'Parse';

  @override
  String get validate => 'Validate';

  @override
  String get generate => 'Generate';

  @override
  String get simulate => 'Preview';

  @override
  String get deploy => 'Deploy';

  @override
  String get train => 'Train';

  @override
  String get hardware => 'Hardware';

  @override
  String get templateGallery => 'Template Gallery';

  @override
  String get chooseTemplate =>
      'Choose a pre-built spec to get started quickly.';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get downloadCnl => 'Download .cnl';

  @override
  String get saveSpecAsCnl => 'Save spec as CNL file';

  @override
  String get exportHtmlReport => 'Export HTML Report';

  @override
  String get reportSubtitle => 'Spec, validation, network, and stats';

  @override
  String get exportPythonScript => 'Export Python Script';

  @override
  String get pythonSubtitle => 'Standalone Nengo script';

  @override
  String get copyShareableLink => 'Copy Shareable Link';

  @override
  String get linkSubtitle => 'Spec encoded in URL';

  @override
  String get simulationSummary => 'Compiled Topology';

  @override
  String get runToSeeResults =>
      'Compile the current spec to inspect topology and NIR here.';

  @override
  String get validationResults => 'Validation results will appear here.';

  @override
  String get layer1 => 'Layer 1 — Biophysical Invariants';

  @override
  String get layer2 => 'Layer 2 — Cross-Sentence Checks';

  @override
  String get neuronsFound => 'Neurons found';

  @override
  String get allInvariantsPassed => 'Validation successful';

  @override
  String get validationFailed => 'Validation failed';

  @override
  String get cnlViewToggle => 'CNL';

  @override
  String get nirViewToggle => 'NIR';

  @override
  String get canvasViewToggle => 'Canvas';

  @override
  String get syncing => 'Syncing…';

  @override
  String get stopSimulation => 'Stop';

  @override
  String get fixErrorsFirst => 'Fix errors first';
}
