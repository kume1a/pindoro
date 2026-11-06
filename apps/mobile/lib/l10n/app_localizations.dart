import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ka.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ka'),
  ];

  /// No description provided for @commonPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// No description provided for @commonXp.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP'**
  String commonXp(String xp);

  /// No description provided for @commonAttribution.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors, Protomaps'**
  String get commonAttribution;

  /// No description provided for @commonChooseCity.
  ///
  /// In en, this message translates to:
  /// **'Choose a city'**
  String get commonChooseCity;

  /// No description provided for @commonQuestionProgress.
  ///
  /// In en, this message translates to:
  /// **'Question {question} of {total}'**
  String commonQuestionProgress(int question, int total);

  /// No description provided for @commonChangeSettings.
  ///
  /// In en, this message translates to:
  /// **'Change settings'**
  String get commonChangeSettings;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Learn any town, street by street.'**
  String get welcomeTagline;

  /// No description provided for @welcomeFindCity.
  ///
  /// In en, this message translates to:
  /// **'Find another city'**
  String get welcomeFindCity;

  /// No description provided for @welcomeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recent cities yet'**
  String get welcomeEmptyTitle;

  /// No description provided for @welcomeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Cities you play will show up here, ready to resume.'**
  String get welcomeEmptyBody;

  /// No description provided for @homeLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String homeLevel(int level);

  /// No description provided for @homeXpToNextLevel.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to level {level}'**
  String homeXpToNextLevel(String xp, int level);

  /// No description provided for @homeXpTotal.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP in total'**
  String homeXpTotal(String xp);

  /// No description provided for @homeKnownTitle.
  ///
  /// In en, this message translates to:
  /// **'Streets you know'**
  String get homeKnownTitle;

  /// No description provided for @homeLegendInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get homeLegendInProgress;

  /// No description provided for @homeLegendComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get homeLegendComplete;

  /// No description provided for @homeLegendNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get homeLegendNotStarted;

  /// No description provided for @homeAllDistricts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} district} other{All {count} districts}}'**
  String homeAllDistricts(int count);

  /// No description provided for @homeEmptyCity.
  ///
  /// In en, this message translates to:
  /// **'No streets known yet. Play a round and the map starts filling in.'**
  String get homeEmptyCity;

  /// No description provided for @homeChooseArea.
  ///
  /// In en, this message translates to:
  /// **'Choose an area'**
  String get homeChooseArea;

  /// No description provided for @homeSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Round in progress'**
  String get homeSavedTitle;

  /// No description provided for @homeSavedAgo.
  ///
  /// In en, this message translates to:
  /// **'saved {time} ago'**
  String homeSavedAgo(String time);

  /// No description provided for @homeSavedXp.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP so far'**
  String homeSavedXp(String xp);

  /// No description provided for @homeContinueRound.
  ///
  /// In en, this message translates to:
  /// **'Continue round'**
  String get homeContinueRound;

  /// No description provided for @homeNewRound.
  ///
  /// In en, this message translates to:
  /// **'Start a new round instead'**
  String get homeNewRound;

  /// No description provided for @homeCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'Your city fills in here'**
  String get homeCoachTitle;

  /// No description provided for @homeCoachBody.
  ///
  /// In en, this message translates to:
  /// **'Every Great or Perfect adds a street you know. Tap anywhere to close.'**
  String get homeCoachBody;

  /// No description provided for @citySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search cities'**
  String get citySearchHint;

  /// No description provided for @cityUseLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get cityUseLocation;

  /// No description provided for @cityUseLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play the streets around you'**
  String get cityUseLocationSubtitle;

  /// No description provided for @cityLocationLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding where you are…'**
  String get cityLocationLocating;

  /// No description provided for @cityLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location is off. Turn it on in Settings.'**
  String get cityLocationDenied;

  /// No description provided for @cityRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get cityRecent;

  /// No description provided for @cityResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} place} other{{count} places}}'**
  String cityResultCount(int count);

  /// No description provided for @citySearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get citySearching;

  /// No description provided for @cityNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No places called “{query}”'**
  String cityNoResultsTitle(String query);

  /// No description provided for @cityNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Check the spelling. Pindoro has these cities so far.'**
  String get cityNoResultsBody;

  /// No description provided for @cityNoResultsSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Did you mean {name}?'**
  String cityNoResultsSuggestion(String name);

  /// No description provided for @cityOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Search needs a connection'**
  String get cityOfflineTitle;

  /// No description provided for @cityOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Your recent cities still open. Their streets load again when you’re back online.'**
  String get cityOfflineBody;

  /// No description provided for @cityPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Play where you are'**
  String get cityPermissionTitle;

  /// No description provided for @cityPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Pindoro checks your location once to find the town you’re in. It isn’t stored or shared.'**
  String get cityPermissionBody;

  /// No description provided for @cityPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow location'**
  String get cityPermissionAllow;

  /// No description provided for @areaModeDistricts.
  ///
  /// In en, this message translates to:
  /// **'Districts'**
  String get areaModeDistricts;

  /// No description provided for @areaModeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get areaModeCircle;

  /// No description provided for @areaModeRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get areaModeRectangle;

  /// No description provided for @areaNamesTwo.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String areaNamesTwo(String first, String second);

  /// No description provided for @areaNamesMore.
  ///
  /// In en, this message translates to:
  /// **'{first} + {count} more'**
  String areaNamesMore(String first, int count);

  /// No description provided for @areaDistrictCount.
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =1{{count} of {total} district} other{{count} of {total} districts}}'**
  String areaDistrictCount(int total, int count);

  /// No description provided for @areaHelp.
  ///
  /// In en, this message translates to:
  /// **'Tap districts on the map or here. Pick one or more.'**
  String get areaHelp;

  /// No description provided for @areaNoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick your districts'**
  String get areaNoneTitle;

  /// No description provided for @areaNoneButton.
  ///
  /// In en, this message translates to:
  /// **'Pick a district first'**
  String get areaNoneButton;

  /// No description provided for @areaPlayArea.
  ///
  /// In en, this message translates to:
  /// **'Play area'**
  String get areaPlayArea;

  /// No description provided for @areaCircleHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag the map to move the circle. Drag its handle or the slider to resize it.'**
  String get areaCircleHelp;

  /// No description provided for @areaRectangleHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag the map to move the rectangle. Drag a corner to resize it.'**
  String get areaRectangleHelp;

  /// No description provided for @areaNoDistricts.
  ///
  /// In en, this message translates to:
  /// **'{city} has no district outlines on the map, so pick a circle or a rectangle.'**
  String areaNoDistricts(String city);

  /// No description provided for @areaSearchDistricts.
  ///
  /// In en, this message translates to:
  /// **'Search districts'**
  String get areaSearchDistricts;

  /// No description provided for @areaPickedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} picked'**
  String areaPickedCount(int count);

  /// No description provided for @areaKnownCount.
  ///
  /// In en, this message translates to:
  /// **'{known} / {total} known'**
  String areaKnownCount(int known, int total);

  /// No description provided for @difficultyTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a difficulty'**
  String get difficultyTitle;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// No description provided for @difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// No description provided for @difficultyExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get difficultyExpert;

  /// No description provided for @difficultyEasyDescription.
  ///
  /// In en, this message translates to:
  /// **'Major roads only'**
  String get difficultyEasyDescription;

  /// No description provided for @difficultyMediumDescription.
  ///
  /// In en, this message translates to:
  /// **'Adds secondary roads'**
  String get difficultyMediumDescription;

  /// No description provided for @difficultyHardDescription.
  ///
  /// In en, this message translates to:
  /// **'Adds tertiary roads'**
  String get difficultyHardDescription;

  /// No description provided for @difficultyExpertDescription.
  ///
  /// In en, this message translates to:
  /// **'Adds residential and small streets'**
  String get difficultyExpertDescription;

  /// No description provided for @difficultyStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get difficultyStart;

  /// No description provided for @setupLoading.
  ///
  /// In en, this message translates to:
  /// **'Finding streets…'**
  String get setupLoading;

  /// No description provided for @setupErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Streets didn’t load'**
  String get setupErrorTitle;

  /// No description provided for @setupErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again. Your city, area and difficulty are saved.'**
  String get setupErrorBody;

  /// No description provided for @setupSparseTitle.
  ///
  /// In en, this message translates to:
  /// **'Not enough streets here'**
  String get setupSparseTitle;

  /// No description provided for @setupSparseBody.
  ///
  /// In en, this message translates to:
  /// **'A round needs 10 streets.'**
  String get setupSparseBody;

  /// No description provided for @setupSparseBiggerCircle.
  ///
  /// In en, this message translates to:
  /// **'Make the circle bigger'**
  String get setupSparseBiggerCircle;

  /// No description provided for @setupSparseAddNeighbour.
  ///
  /// In en, this message translates to:
  /// **'Add a neighbouring district'**
  String get setupSparseAddNeighbour;

  /// No description provided for @setupSparseSwitchDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Switch to {difficulty}'**
  String setupSparseSwitchDifficulty(String difficulty);

  /// No description provided for @quizPrompt.
  ///
  /// In en, this message translates to:
  /// **'Drop a pin on'**
  String get quizPrompt;

  /// No description provided for @quizRetryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Try again: drop a pin on'**
  String get quizRetryPrompt;

  /// No description provided for @quizRetryPreviousDistance.
  ///
  /// In en, this message translates to:
  /// **'you were {distance} away'**
  String quizRetryPreviousDistance(String distance);

  /// No description provided for @quizCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop a pin where you think this street is'**
  String get quizCoachTitle;

  /// No description provided for @quizCoachBody.
  ///
  /// In en, this message translates to:
  /// **'You can drag it before you confirm.'**
  String get quizCoachBody;

  /// No description provided for @quizLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave for now?'**
  String get quizLeaveTitle;

  /// No description provided for @quizLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Your round is saved at question {question} of {total}, with the {xp} XP you’ve earned. Pick it up from Home.'**
  String quizLeaveBody(int question, int total, String xp);

  /// No description provided for @quizLeaveKeepPlaying.
  ///
  /// In en, this message translates to:
  /// **'Keep playing'**
  String get quizLeaveKeepPlaying;

  /// No description provided for @quizLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave for now'**
  String get quizLeaveConfirm;

  /// No description provided for @toastPinOutsideArea.
  ///
  /// In en, this message translates to:
  /// **'Your street is inside the circle. You can still confirm here.'**
  String get toastPinOutsideArea;

  /// No description provided for @toastOffline.
  ///
  /// In en, this message translates to:
  /// **'You’re offline. The map has gaps, but your round still works.'**
  String get toastOffline;

  /// No description provided for @toastRoundResumed.
  ///
  /// In en, this message translates to:
  /// **'Welcome back. Your round continues at question {question}.'**
  String toastRoundResumed(int question);

  /// No description provided for @tierPerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect!'**
  String get tierPerfect;

  /// No description provided for @tierGreat.
  ///
  /// In en, this message translates to:
  /// **'Great!'**
  String get tierGreat;

  /// No description provided for @tierClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tierClose;

  /// No description provided for @tierMiss.
  ///
  /// In en, this message translates to:
  /// **'Not this time'**
  String get tierMiss;

  /// No description provided for @tierPerfectWord.
  ///
  /// In en, this message translates to:
  /// **'Perfect'**
  String get tierPerfectWord;

  /// No description provided for @tierGreatWord.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get tierGreatWord;

  /// No description provided for @tierMissWord.
  ///
  /// In en, this message translates to:
  /// **'Miss'**
  String get tierMissWord;

  /// No description provided for @tierPerfectSentence.
  ///
  /// In en, this message translates to:
  /// **'On the street. You know this city.'**
  String get tierPerfectSentence;

  /// No description provided for @tierGreatSentence.
  ///
  /// In en, this message translates to:
  /// **'{distance} away. So close to perfect.'**
  String tierGreatSentence(String distance);

  /// No description provided for @tierCloseSentence.
  ///
  /// In en, this message translates to:
  /// **'{distance} away. You’re in the right neighbourhood.'**
  String tierCloseSentence(String distance);

  /// No description provided for @tierMissSentence.
  ///
  /// In en, this message translates to:
  /// **'{distance} away. {hint} You’ll see it again on your results.'**
  String tierMissSentence(String distance, String hint);

  /// No description provided for @revealStreak.
  ///
  /// In en, this message translates to:
  /// **'{count} in a row'**
  String revealStreak(int count);

  /// No description provided for @revealGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get revealGotIt;

  /// No description provided for @revealSeeResults.
  ///
  /// In en, this message translates to:
  /// **'See results'**
  String get revealSeeResults;

  /// No description provided for @resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Round complete!'**
  String get resultsTitle;

  /// No description provided for @resultsFlawless.
  ///
  /// In en, this message translates to:
  /// **'Flawless round!'**
  String get resultsFlawless;

  /// No description provided for @resultsRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Retry complete'**
  String get resultsRetryTitle;

  /// No description provided for @resultsStreetsKnown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+{count} street known} other{+{count} streets known}}'**
  String resultsStreetsKnown(int count);

  /// No description provided for @resultsYourStreets.
  ///
  /// In en, this message translates to:
  /// **'Your streets'**
  String get resultsYourStreets;

  /// No description provided for @resultsRetryMissed.
  ///
  /// In en, this message translates to:
  /// **'Retry {count} missed'**
  String resultsRetryMissed(int count);

  /// No description provided for @resultsNoRetry.
  ///
  /// In en, this message translates to:
  /// **'No streets to retry'**
  String get resultsNoRetry;

  /// No description provided for @resultsToRetry.
  ///
  /// In en, this message translates to:
  /// **'to retry'**
  String get resultsToRetry;

  /// No description provided for @resultsOnStreet.
  ///
  /// In en, this message translates to:
  /// **'On the street'**
  String get resultsOnStreet;

  /// No description provided for @resultsPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get resultsPlayAgain;

  /// No description provided for @resultsNewRound.
  ///
  /// In en, this message translates to:
  /// **'Play a new round'**
  String get resultsNewRound;

  /// No description provided for @levelUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Level {level}!'**
  String levelUpTitle(int level);

  /// No description provided for @levelUpBody.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP in total. Every Great and Perfect got you here.'**
  String levelUpBody(String xp);

  /// No description provided for @levelUpNext.
  ///
  /// In en, this message translates to:
  /// **'Next: level {level}'**
  String levelUpNext(int level);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsStreetNames.
  ///
  /// In en, this message translates to:
  /// **'Street names'**
  String get settingsStreetNames;

  /// No description provided for @settingsStreetNamesLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get settingsStreetNamesLocal;

  /// No description provided for @settingsStreetNamesEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsStreetNamesEnglish;

  /// No description provided for @settingsStreetNamesHelp.
  ///
  /// In en, this message translates to:
  /// **'English shows when the map has it, otherwise the local name.'**
  String get settingsStreetNamesHelp;

  /// No description provided for @settingsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display and feedback'**
  String get settingsDisplay;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsSoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chimes, taps and celebrations'**
  String get settingsSoundSubtitle;

  /// No description provided for @settingsHaptics.
  ///
  /// In en, this message translates to:
  /// **'Haptics'**
  String get settingsHaptics;

  /// No description provided for @settingsHapticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Buzz on pin drop and answers'**
  String get settingsHapticsSubtitle;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @creditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Map data credits'**
  String get creditsTitle;

  /// No description provided for @creditsIntro.
  ///
  /// In en, this message translates to:
  /// **'Pindoro is built on open map data. Thank you to everyone who maps their streets.'**
  String get creditsIntro;

  /// No description provided for @creditsFix.
  ///
  /// In en, this message translates to:
  /// **'Spotted a missing or wrong street? Fix it on openstreetmap.org and Pindoro picks it up within a few weeks.'**
  String get creditsFix;

  /// No description provided for @creditsOsm.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get creditsOsm;

  /// No description provided for @creditsOsmLicence.
  ///
  /// In en, this message translates to:
  /// **'Map data is available under the Open Database License (ODbL).'**
  String get creditsOsmLicence;

  /// No description provided for @creditsOsmLink.
  ///
  /// In en, this message translates to:
  /// **'openstreetmap.org/copyright'**
  String get creditsOsmLink;

  /// No description provided for @creditsTiles.
  ///
  /// In en, this message translates to:
  /// **'Map tiles: Protomaps'**
  String get creditsTiles;

  /// No description provided for @creditsFont.
  ///
  /// In en, this message translates to:
  /// **'Font: FiraGO (SIL Open Font License)'**
  String get creditsFont;

  /// No description provided for @a11yLeaveRound.
  ///
  /// In en, this message translates to:
  /// **'Leave round'**
  String get a11yLeaveRound;

  /// No description provided for @a11yFindStreet.
  ///
  /// In en, this message translates to:
  /// **'Find: {name}, {altName}'**
  String a11yFindStreet(String name, String altName);

  /// No description provided for @a11yMap.
  ///
  /// In en, this message translates to:
  /// **'Map. Double-tap to drop your pin at the centre.'**
  String get a11yMap;

  /// No description provided for @a11yPin.
  ///
  /// In en, this message translates to:
  /// **'Your pin. Double-tap and hold to move.'**
  String get a11yPin;

  /// No description provided for @a11yConfirmDisabled.
  ///
  /// In en, this message translates to:
  /// **'Confirm. Drop a pin first.'**
  String get a11yConfirmDisabled;

  /// No description provided for @a11yReveal.
  ///
  /// In en, this message translates to:
  /// **'{tier}. {distance} away. Plus {xp} XP.'**
  String a11yReveal(String tier, String distance, String xp);

  /// No description provided for @a11yLevelProgress.
  ///
  /// In en, this message translates to:
  /// **'Level {level}, {xp} of {xpNeeded} XP'**
  String a11yLevelProgress(int level, String xp, String xpNeeded);

  /// No description provided for @a11yGoToMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Go to my location'**
  String get a11yGoToMyLocation;

  /// No description provided for @a11yRecentre.
  ///
  /// In en, this message translates to:
  /// **'Recentre'**
  String get a11yRecentre;

  /// No description provided for @a11yZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get a11yZoomIn;

  /// No description provided for @a11yZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get a11yZoomOut;

  /// The {hint} of a Miss: which way the street lies from the pin (n, ne, e, se, s, sw, w, nw).
  ///
  /// In en, this message translates to:
  /// **'{direction, select, n{It’s north of your pin.} ne{It’s north-east of your pin.} e{It’s east of your pin.} se{It’s south-east of your pin.} s{It’s south of your pin.} sw{It’s south-west of your pin.} w{It’s west of your pin.} nw{It’s north-west of your pin.} other{It’s close to your pin.}}'**
  String revealMissDirection(String direction);

  /// No description provided for @a11yFindStreetName.
  ///
  /// In en, this message translates to:
  /// **'Find: {name}'**
  String a11yFindStreetName(String name);

  /// No description provided for @a11yRoundXp.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP this round'**
  String a11yRoundXp(String xp);

  /// No description provided for @a11yResultRow.
  ///
  /// In en, this message translates to:
  /// **'Question {question}. {street}. {tier}, {distance}, plus {xp} XP. Show on map.'**
  String a11yResultRow(
    int question,
    String street,
    String tier,
    String distance,
    String xp,
  );

  /// No description provided for @resultsPreviousStreet.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get resultsPreviousStreet;

  /// No description provided for @resultsNextStreet.
  ///
  /// In en, this message translates to:
  /// **'Next street'**
  String get resultsNextStreet;

  /// No description provided for @resultsBackToResults.
  ///
  /// In en, this message translates to:
  /// **'Back to results'**
  String get resultsBackToResults;

  /// No description provided for @a11yRewardTotal.
  ///
  /// In en, this message translates to:
  /// **'Plus {xp} XP this round'**
  String a11yRewardTotal(String xp);

  /// No description provided for @a11yTierTally.
  ///
  /// In en, this message translates to:
  /// **'{perfect} Perfect, {great} Great, {close} Close, {miss} Miss'**
  String a11yTierTally(int perfect, int great, int close, int miss);

  /// No description provided for @setupSparseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This area has 1 street at {difficulty}.} other{This area has {count} streets at {difficulty}.}}'**
  String setupSparseCount(int count, String difficulty);

  /// No description provided for @setupAreaMissingBody.
  ///
  /// In en, this message translates to:
  /// **'The streets for this area aren’t on your phone yet. Pick an area from the ones you have.'**
  String get setupAreaMissingBody;

  /// No description provided for @areaCircleName.
  ///
  /// In en, this message translates to:
  /// **'{size} circle'**
  String areaCircleName(String size);

  /// No description provided for @areaRectangleName.
  ///
  /// In en, this message translates to:
  /// **'{size} rectangle'**
  String areaRectangleName(String size);

  /// No description provided for @difficultyScoringTitle.
  ///
  /// In en, this message translates to:
  /// **'How close counts at {difficulty}'**
  String difficultyScoringTitle(String difficulty);

  /// No description provided for @difficultyWithin.
  ///
  /// In en, this message translates to:
  /// **'Within {distance}'**
  String difficultyWithin(String distance);

  /// No description provided for @cityNoneNearby.
  ///
  /// In en, this message translates to:
  /// **'No city near you yet. Pick one from the list.'**
  String get cityNoneNearby;

  /// No description provided for @cityAll.
  ///
  /// In en, this message translates to:
  /// **'All cities'**
  String get cityAll;

  /// No description provided for @cityClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get cityClearSearch;

  /// No description provided for @a11yCitySwitcher.
  ///
  /// In en, this message translates to:
  /// **'City: {city}. Change city.'**
  String a11yCitySwitcher(String city);

  /// No description provided for @a11yPlay.
  ///
  /// In en, this message translates to:
  /// **'Play {what}'**
  String a11yPlay(String what);

  /// No description provided for @a11ySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get a11ySettings;

  /// No description provided for @homeXpTotalShort.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP'**
  String homeXpTotalShort(String xp);

  /// No description provided for @homeKnownOf.
  ///
  /// In en, this message translates to:
  /// **'{known} / {total}'**
  String homeKnownOf(String known, String total);

  /// No description provided for @homeSavedProgress.
  ///
  /// In en, this message translates to:
  /// **'Question {question} of {total} · {xp} XP so far'**
  String homeSavedProgress(int question, int total, String xp);

  /// No description provided for @unitMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String unitMinutes(int count);

  /// No description provided for @unitHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String unitHours(int count);

  /// No description provided for @unitDays.
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String unitDays(int count);
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
      <String>['en', 'ka'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ka':
      return AppLocalizationsKa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
