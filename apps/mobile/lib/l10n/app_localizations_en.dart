// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonPlay => 'Play';

  @override
  String get commonNext => 'Next';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonBack => 'Back';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonDone => 'Done';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonNotNow => 'Not now';

  @override
  String commonXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get commonAttribution => '© OpenStreetMap contributors, Protomaps';

  @override
  String get commonChooseCity => 'Choose a city';

  @override
  String commonQuestionProgress(int question, int total) {
    return 'Question $question of $total';
  }

  @override
  String get commonChangeSettings => 'Change settings';

  @override
  String get welcomeTagline => 'Learn any town, street by street.';

  @override
  String get welcomeFindCity => 'Find another city';

  @override
  String get welcomeEmptyTitle => 'No recent cities yet';

  @override
  String get welcomeEmptyBody =>
      'Cities you play will show up here, ready to resume.';

  @override
  String homeLevel(int level) {
    return 'Level $level';
  }

  @override
  String homeXpToNextLevel(int xp, int level) {
    return '$xp XP to level $level';
  }

  @override
  String homeXpTotal(int xp) {
    return '$xp XP in total';
  }

  @override
  String get homeKnownTitle => 'Streets you know';

  @override
  String get homeLegendInProgress => 'In progress';

  @override
  String get homeLegendComplete => 'Complete';

  @override
  String get homeLegendNotStarted => 'Not started';

  @override
  String homeAllDistricts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count districts',
      one: '$count district',
    );
    return '$_temp0';
  }

  @override
  String get homeEmptyCity =>
      'No streets known yet. Play a round and the map starts filling in.';

  @override
  String get homeChooseArea => 'Choose an area';

  @override
  String get homeSavedTitle => 'Round in progress';

  @override
  String homeSavedAgo(String time) {
    return 'saved $time ago';
  }

  @override
  String homeSavedXp(int xp) {
    return '$xp XP so far';
  }

  @override
  String get homeContinueRound => 'Continue round';

  @override
  String get homeNewRound => 'Start a new round instead';

  @override
  String get homeCoachTitle => 'Your city fills in here';

  @override
  String get homeCoachBody =>
      'Every Great or Perfect adds a street you know. Tap anywhere to close.';

  @override
  String get citySearchHint => 'Search any city or town';

  @override
  String get cityUseLocation => 'Use my location';

  @override
  String get cityUseLocationSubtitle => 'Play the streets around you';

  @override
  String get cityLocationLocating => 'Finding where you are…';

  @override
  String get cityLocationDenied => 'Location is off. Turn it on in Settings.';

  @override
  String get cityRecent => 'Recent';

  @override
  String cityResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '$count place',
    );
    return '$_temp0';
  }

  @override
  String get citySearching => 'Searching…';

  @override
  String cityNoResultsTitle(String query) {
    return 'No places called “$query”';
  }

  @override
  String get cityNoResultsBody => 'Check the spelling, or try a nearby town.';

  @override
  String cityNoResultsSuggestion(String name) {
    return 'Did you mean $name?';
  }

  @override
  String get cityOfflineTitle => 'Search needs a connection';

  @override
  String get cityOfflineBody =>
      'Your recent cities still open. Their streets load again when you’re back online.';

  @override
  String get cityPermissionTitle => 'Play where you are';

  @override
  String get cityPermissionBody =>
      'Pindoro checks your location once to find the town you’re in. It isn’t stored or shared.';

  @override
  String get cityPermissionAllow => 'Allow location';

  @override
  String get areaModeDistricts => 'Districts';

  @override
  String get areaModeCircle => 'Circle';

  @override
  String get areaModeRectangle => 'Rectangle';

  @override
  String areaNamesTwo(String first, String second) {
    return '$first and $second';
  }

  @override
  String areaNamesMore(String first, int count) {
    return '$first + $count more';
  }

  @override
  String areaDistrictCount(int total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$count of $total districts',
      one: '$count of $total district',
    );
    return '$_temp0';
  }

  @override
  String get areaHelp => 'Tap districts on the map or here. Pick one or more.';

  @override
  String get areaNoneTitle => 'Pick your districts';

  @override
  String get areaNoneButton => 'Pick a district first';

  @override
  String get areaPlayArea => 'Play area';

  @override
  String get areaCircleHelp =>
      'Drag the map to move the circle. Drag its handle or the slider to resize it.';

  @override
  String get areaRectangleHelp =>
      'Drag the map to move the rectangle. Drag a corner to resize it.';

  @override
  String areaNoDistricts(String city) {
    return '$city has no district outlines on the map, so pick a circle or a rectangle.';
  }

  @override
  String get areaSearchDistricts => 'Search districts';

  @override
  String areaPickedCount(int count) {
    return '$count picked';
  }

  @override
  String areaKnownCount(int known, int total) {
    return '$known / $total known';
  }

  @override
  String get difficultyTitle => 'Choose a difficulty';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyMedium => 'Medium';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get difficultyExpert => 'Expert';

  @override
  String get difficultyEasyDescription => 'Major roads only';

  @override
  String get difficultyMediumDescription => 'Adds secondary roads';

  @override
  String get difficultyHardDescription => 'Adds tertiary roads';

  @override
  String get difficultyExpertDescription =>
      'Adds residential and small streets';

  @override
  String get difficultyStart => 'Start';

  @override
  String get setupLoading => 'Finding streets…';

  @override
  String get setupErrorTitle => 'Streets didn’t load';

  @override
  String get setupErrorBody =>
      'Check your connection and try again. Your city, area and difficulty are saved.';

  @override
  String get setupSparseTitle => 'Not enough streets here';

  @override
  String get setupSparseBody => 'A round needs 10 streets.';

  @override
  String get setupSparseBiggerCircle => 'Make the circle bigger';

  @override
  String get setupSparseAddNeighbour => 'Add a neighbouring district';

  @override
  String setupSparseSwitchDifficulty(String difficulty) {
    return 'Switch to $difficulty';
  }

  @override
  String get quizPrompt => 'Drop a pin on';

  @override
  String get quizRetryPrompt => 'Try again: drop a pin on';

  @override
  String quizRetryPreviousDistance(String distance) {
    return 'you were $distance away';
  }

  @override
  String get quizCoachTitle => 'Drop a pin where you think this street is';

  @override
  String get quizCoachBody => 'You can drag it before you confirm.';

  @override
  String get quizLeaveTitle => 'Leave for now?';

  @override
  String quizLeaveBody(int question, int total, int xp) {
    return 'Your round is saved at question $question of $total, with the $xp XP you’ve earned. Pick it up from Home.';
  }

  @override
  String get quizLeaveKeepPlaying => 'Keep playing';

  @override
  String get quizLeaveConfirm => 'Leave for now';

  @override
  String get toastPinOutsideArea =>
      'Your street is inside the circle. You can still confirm here.';

  @override
  String get toastOffline =>
      'You’re offline. The map has gaps, but your round still works.';

  @override
  String toastRoundResumed(int question) {
    return 'Welcome back. Your round continues at question $question.';
  }

  @override
  String get tierPerfect => 'Perfect!';

  @override
  String get tierGreat => 'Great!';

  @override
  String get tierClose => 'Close';

  @override
  String get tierMiss => 'Not this time';

  @override
  String get tierPerfectWord => 'Perfect';

  @override
  String get tierGreatWord => 'Great';

  @override
  String get tierMissWord => 'Miss';

  @override
  String get tierPerfectSentence => 'On the street. You know this city.';

  @override
  String tierGreatSentence(String distance) {
    return '$distance away. So close to perfect.';
  }

  @override
  String tierCloseSentence(String distance) {
    return '$distance away. You’re in the right neighbourhood.';
  }

  @override
  String tierMissSentence(String distance, String hint) {
    return '$distance away. $hint You’ll see it again on your results.';
  }

  @override
  String revealStreak(int count) {
    return '$count in a row';
  }

  @override
  String get revealGotIt => 'Got it';

  @override
  String get revealSeeResults => 'See results';

  @override
  String get resultsTitle => 'Round complete!';

  @override
  String get resultsFlawless => 'Flawless round!';

  @override
  String get resultsRetryTitle => 'Retry complete';

  @override
  String resultsStreetsKnown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count streets known',
      one: '+$count street known',
    );
    return '$_temp0';
  }

  @override
  String get resultsYourStreets => 'Your streets';

  @override
  String resultsRetryMissed(int count) {
    return 'Retry $count missed';
  }

  @override
  String get resultsNoRetry => 'No streets to retry';

  @override
  String get resultsToRetry => 'to retry';

  @override
  String get resultsOnStreet => 'On the street';

  @override
  String get resultsPlayAgain => 'Play again';

  @override
  String get resultsNewRound => 'Play a new round';

  @override
  String levelUpTitle(int level) {
    return 'Level $level!';
  }

  @override
  String levelUpBody(int xp) {
    return '$xp XP in total. Every Great and Perfect got you here.';
  }

  @override
  String levelUpNext(int level) {
    return 'Next: level $level';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsStreetNames => 'Street names';

  @override
  String get settingsStreetNamesLocal => 'Local';

  @override
  String get settingsStreetNamesEnglish => 'English';

  @override
  String get settingsStreetNamesHelp =>
      'English shows when the map has it, otherwise the local name.';

  @override
  String get settingsDisplay => 'Display and feedback';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsSoundSubtitle => 'Chimes, taps and celebrations';

  @override
  String get settingsHaptics => 'Haptics';

  @override
  String get settingsHapticsSubtitle => 'Buzz on pin drop and answers';

  @override
  String get settingsAbout => 'About';

  @override
  String get creditsTitle => 'Map data credits';

  @override
  String get creditsIntro =>
      'Pindoro is built on open map data. Thank you to everyone who maps their streets.';

  @override
  String get creditsFix =>
      'Spotted a missing or wrong street? Fix it on openstreetmap.org and Pindoro picks it up within a few weeks.';

  @override
  String get creditsOsm => '© OpenStreetMap contributors';

  @override
  String get creditsOsmLicence =>
      'Map data is available under the Open Database License (ODbL).';

  @override
  String get creditsOsmLink => 'openstreetmap.org/copyright';

  @override
  String get creditsTiles => 'Map tiles: Protomaps';

  @override
  String get creditsFont => 'Font: FiraGO (SIL Open Font License)';

  @override
  String get a11yLeaveRound => 'Leave round';

  @override
  String a11yFindStreet(String name, String altName) {
    return 'Find: $name, $altName';
  }

  @override
  String get a11yMap => 'Map. Double-tap to drop your pin at the centre.';

  @override
  String get a11yPin => 'Your pin. Double-tap and hold to move.';

  @override
  String get a11yConfirmDisabled => 'Confirm. Drop a pin first.';

  @override
  String a11yReveal(String tier, String distance, int xp) {
    return '$tier. $distance away. Plus $xp XP.';
  }

  @override
  String a11yLevelProgress(int level, int xp, int xpNeeded) {
    return 'Level $level, $xp of $xpNeeded XP';
  }

  @override
  String get a11yGoToMyLocation => 'Go to my location';

  @override
  String get a11yRecentre => 'Recentre';

  @override
  String get a11yZoomIn => 'Zoom in';

  @override
  String get a11yZoomOut => 'Zoom out';
}
