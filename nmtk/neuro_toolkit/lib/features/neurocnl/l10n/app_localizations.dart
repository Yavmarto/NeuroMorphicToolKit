import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'neurocnl Studio'**
  String get appTitle;

  /// No description provided for @templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// No description provided for @runSimulation.
  ///
  /// In en, this message translates to:
  /// **'Run compiled model'**
  String get runSimulation;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get running;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @cnlEditor.
  ///
  /// In en, this message translates to:
  /// **'CNL Editor'**
  String get cnlEditor;

  /// No description provided for @sentences.
  ///
  /// In en, this message translates to:
  /// **'sentences'**
  String get sentences;

  /// No description provided for @lines.
  ///
  /// In en, this message translates to:
  /// **'lines'**
  String get lines;

  /// No description provided for @parsedSpecs.
  ///
  /// In en, this message translates to:
  /// **'Parsed Specs'**
  String get parsedSpecs;

  /// No description provided for @validation.
  ///
  /// In en, this message translates to:
  /// **'Validation'**
  String get validation;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @simulation.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get simulation;

  /// No description provided for @parameters.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get parameters;

  /// No description provided for @parse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get parse;

  /// No description provided for @validate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get validate;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @simulate.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get simulate;

  /// No description provided for @deploy.
  ///
  /// In en, this message translates to:
  /// **'Deploy'**
  String get deploy;

  /// No description provided for @train.
  ///
  /// In en, this message translates to:
  /// **'Train'**
  String get train;

  /// No description provided for @hardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get hardware;

  /// No description provided for @templateGallery.
  ///
  /// In en, this message translates to:
  /// **'Template Gallery'**
  String get templateGallery;

  /// No description provided for @chooseTemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose a pre-built spec to get started quickly.'**
  String get chooseTemplate;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @downloadCnl.
  ///
  /// In en, this message translates to:
  /// **'Download .cnl'**
  String get downloadCnl;

  /// No description provided for @saveSpecAsCnl.
  ///
  /// In en, this message translates to:
  /// **'Save spec as CNL file'**
  String get saveSpecAsCnl;

  /// No description provided for @exportHtmlReport.
  ///
  /// In en, this message translates to:
  /// **'Export HTML Report'**
  String get exportHtmlReport;

  /// No description provided for @reportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Spec, validation, network, and stats'**
  String get reportSubtitle;

  /// No description provided for @exportPythonScript.
  ///
  /// In en, this message translates to:
  /// **'Export Python Script'**
  String get exportPythonScript;

  /// No description provided for @pythonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Standalone Nengo script'**
  String get pythonSubtitle;

  /// No description provided for @copyShareableLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Shareable Link'**
  String get copyShareableLink;

  /// No description provided for @linkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Spec encoded in URL'**
  String get linkSubtitle;

  /// No description provided for @simulationSummary.
  ///
  /// In en, this message translates to:
  /// **'Compiled Topology'**
  String get simulationSummary;

  /// No description provided for @runToSeeResults.
  ///
  /// In en, this message translates to:
  /// **'Compile the current spec to inspect topology and NIR here.'**
  String get runToSeeResults;

  /// No description provided for @validationResults.
  ///
  /// In en, this message translates to:
  /// **'Validation results will appear here.'**
  String get validationResults;

  /// No description provided for @layer1.
  ///
  /// In en, this message translates to:
  /// **'Layer 1 — Biophysical Invariants'**
  String get layer1;

  /// No description provided for @layer2.
  ///
  /// In en, this message translates to:
  /// **'Layer 2 — Cross-Sentence Checks'**
  String get layer2;

  /// No description provided for @neuronsFound.
  ///
  /// In en, this message translates to:
  /// **'Neurons found'**
  String get neuronsFound;

  /// No description provided for @allInvariantsPassed.
  ///
  /// In en, this message translates to:
  /// **'Validation successful'**
  String get allInvariantsPassed;

  /// No description provided for @validationFailed.
  ///
  /// In en, this message translates to:
  /// **'Validation failed'**
  String get validationFailed;

  /// No description provided for @cnlViewToggle.
  ///
  /// In en, this message translates to:
  /// **'CNL'**
  String get cnlViewToggle;

  /// No description provided for @nirViewToggle.
  ///
  /// In en, this message translates to:
  /// **'NIR'**
  String get nirViewToggle;

  /// No description provided for @canvasViewToggle.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get canvasViewToggle;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @stopSimulation.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopSimulation;

  /// No description provided for @fixErrorsFirst.
  ///
  /// In en, this message translates to:
  /// **'Fix errors first'**
  String get fixErrorsFirst;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
