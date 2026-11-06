// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Georgian (`ka`).
class AppLocalizationsKa extends AppLocalizations {
  AppLocalizationsKa([String locale = 'ka']) : super(locale);

  @override
  String get commonPlay => 'ითამაშე';

  @override
  String get commonNext => 'შემდეგი';

  @override
  String get commonConfirm => 'დადასტურება';

  @override
  String get commonBack => 'უკან';

  @override
  String get commonTryAgain => 'თავიდან ცდა';

  @override
  String get commonContinue => 'გაგრძელება';

  @override
  String get commonDone => 'მზადაა';

  @override
  String get commonCancel => 'გაუქმება';

  @override
  String get commonNotNow => 'ახლა არა';

  @override
  String commonXp(String xp) {
    return '+$xp XP';
  }

  @override
  String get commonAttribution => '© OpenStreetMap contributors, Protomaps';

  @override
  String get commonChooseCity => 'აირჩიე ქალაქი';

  @override
  String commonQuestionProgress(int question, int total) {
    return 'კითხვა $question / $total';
  }

  @override
  String get commonChangeSettings => 'პარამეტრების შეცვლა';

  @override
  String get welcomeTagline => 'ისწავლე ნებისმიერი ქალაქი, ქუჩა-ქუჩა.';

  @override
  String get welcomeFindCity => 'სხვა ქალაქის პოვნა';

  @override
  String get welcomeEmptyTitle => 'ჯერ არცერთ ქალაქში არ გითამაშია';

  @override
  String get welcomeEmptyBody => 'ქალაქები, სადაც ითამაშებ, აქ გამოჩნდება.';

  @override
  String homeLevel(int level) {
    return 'დონე $level';
  }

  @override
  String homeXpToNextLevel(String xp, int level) {
    return 'მე-$level დონემდე $xp XP';
  }

  @override
  String homeXpTotal(String xp) {
    return 'სულ $xp XP';
  }

  @override
  String get homeKnownTitle => 'ქუჩები, რომლებიც იცი';

  @override
  String get homeLegendInProgress => 'მიმდინარე';

  @override
  String get homeLegendComplete => 'დასრულებული';

  @override
  String get homeLegendNotStarted => 'დაუწყებელი';

  @override
  String homeAllDistricts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ყველა $count უბანი',
    );
    return '$_temp0';
  }

  @override
  String get homeEmptyCity =>
      'ჯერ არცერთი ქუჩა არ იცი. ითამაშე რაუნდი და რუკა შეივსება.';

  @override
  String get homeChooseArea => 'აირჩიე არეალი';

  @override
  String get homeSavedTitle => 'დაუსრულებელი რაუნდი';

  @override
  String homeSavedAgo(String time) {
    return 'შენახულია $time წინ';
  }

  @override
  String homeSavedXp(String xp) {
    return 'ჯერჯერობით $xp XP';
  }

  @override
  String get homeContinueRound => 'რაუნდის გაგრძელება';

  @override
  String get homeNewRound => 'ახალი რაუნდის დაწყება';

  @override
  String get homeCoachTitle => 'აქ შენი ქალაქი ივსება';

  @override
  String get homeCoachBody =>
      'ყოველი შესანიშნავი ან იდეალური პასუხი ახალ ნაცნობ ქუჩას ამატებს. დასახურად შეეხე ეკრანს.';

  @override
  String get citySearchHint => 'ქალაქის ძებნა';

  @override
  String get cityUseLocation => 'ჩემი მდებარეობა';

  @override
  String get cityUseLocationSubtitle => 'ითამაშე შენ ირგვლივ ქუჩებზე';

  @override
  String get cityLocationLocating => 'ვარკვევთ, სად ხარ…';

  @override
  String get cityLocationDenied => 'მდებარეობა გამორთულია. ჩართე პარამეტრებში.';

  @override
  String get cityRecent => 'ბოლოს ნათამაშები';

  @override
  String cityResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ადგილი',
    );
    return '$_temp0';
  }

  @override
  String get citySearching => 'ვეძებთ…';

  @override
  String cityNoResultsTitle(String query) {
    return '„$query“ ვერ მოიძებნა';
  }

  @override
  String get cityNoResultsBody =>
      'შეამოწმე მართლწერა. ამ ეტაპზე პინდოროში ეს ქალაქებია.';

  @override
  String cityNoResultsSuggestion(String name) {
    return 'ხომ არ გულისხმობდი: $name?';
  }

  @override
  String get cityOfflineTitle => 'ძებნას ინტერნეტი სჭირდება';

  @override
  String get cityOfflineBody =>
      'ბოლო ქალაქები მაინც იხსნება. ქუჩები ინტერნეტის დაბრუნებისას ჩაიტვირთება.';

  @override
  String get cityPermissionTitle => 'ითამაშე იქ, სადაც ხარ';

  @override
  String get cityPermissionBody =>
      'პინდორო ერთხელ ამოწმებს შენს მდებარეობას, რომ იპოვოს ქალაქი, სადაც ხარ. ის არ ინახება და არავის გადაეცემა.';

  @override
  String get cityPermissionAllow => 'მდებარეობის დაშვება';

  @override
  String get areaModeDistricts => 'უბნები';

  @override
  String get areaModeCircle => 'წრე';

  @override
  String get areaModeRectangle => 'მართკუთხედი';

  @override
  String areaNamesTwo(String first, String second) {
    return '$first და $second';
  }

  @override
  String areaNamesMore(String first, int count) {
    return '$first და კიდევ $count';
  }

  @override
  String areaDistrictCount(int total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$count / $total უბანი',
    );
    return '$_temp0';
  }

  @override
  String get areaHelp => 'შეეხე უბნებს რუკაზე ან აქ. აირჩიე ერთი ან მეტი.';

  @override
  String get areaNoneTitle => 'აირჩიე უბნები';

  @override
  String get areaNoneButton => 'ჯერ აირჩიე უბანი';

  @override
  String get areaPlayArea => 'სათამაშო არეალი';

  @override
  String get areaCircleHelp =>
      'წრის გადასაადგილებლად გადაათრიე რუკა. ზომის შესაცვლელად — სახელური ან სლაიდერი.';

  @override
  String get areaRectangleHelp =>
      'მართკუთხედის გადასაადგილებლად გადაათრიე რუკა. ზომის შესაცვლელად — კუთხე.';

  @override
  String areaNoDistricts(String city) {
    return 'ამ ქალაქს რუკაზე უბნების საზღვრები არ აქვს, ამიტომ აირჩიე წრე ან მართკუთხედი.';
  }

  @override
  String get areaSearchDistricts => 'უბნის ძებნა';

  @override
  String areaPickedCount(int count) {
    return 'არჩეულია $count';
  }

  @override
  String areaKnownCount(int known, int total) {
    return 'ნაცნობი: $known / $total';
  }

  @override
  String get difficultyTitle => 'აირჩიე სირთულე';

  @override
  String get difficultyEasy => 'მარტივი';

  @override
  String get difficultyMedium => 'საშუალო';

  @override
  String get difficultyHard => 'რთული';

  @override
  String get difficultyExpert => 'ექსპერტი';

  @override
  String get difficultyEasyDescription => 'მხოლოდ მთავარი გზები';

  @override
  String get difficultyMediumDescription => '+ მეორეხარისხოვანი გზები';

  @override
  String get difficultyHardDescription => '+ მესამეხარისხოვანი გზები';

  @override
  String get difficultyExpertDescription => '+ საცხოვრებელი და პატარა ქუჩები';

  @override
  String get difficultyStart => 'დაწყება';

  @override
  String get setupLoading => 'ქუჩებს ვეძებთ…';

  @override
  String get setupErrorTitle => 'ქუჩები ვერ ჩაიტვირთა';

  @override
  String get setupErrorBody =>
      'შეამოწმე ინტერნეტი და სცადე თავიდან. ქალაქი, არეალი და სირთულე შენახულია.';

  @override
  String get setupSparseTitle => 'აქ საკმარისი ქუჩა არ არის';

  @override
  String get setupSparseBody => 'რაუნდს 10 ქუჩა სჭირდება.';

  @override
  String get setupSparseBiggerCircle => 'წრის გადიდება';

  @override
  String get setupSparseAddNeighbour => 'მეზობელი უბნის დამატება';

  @override
  String setupSparseSwitchDifficulty(String difficulty) {
    return 'გადართე: $difficulty';
  }

  @override
  String get quizPrompt => 'მონიშნე რუკაზე:';

  @override
  String get quizRetryPrompt => 'კიდევ სცადე, მონიშნე:';

  @override
  String quizRetryPreviousDistance(String distance) {
    return 'წინა ჯერზე: $distance';
  }

  @override
  String get quizCoachTitle => 'მონიშნე, სად გგონია, რომ ეს ქუჩაა';

  @override
  String get quizCoachBody => 'დადასტურებამდე შეგიძლია გადაიტანო.';

  @override
  String get quizLeaveTitle => 'ახლა გადიხარ?';

  @override
  String quizLeaveBody(int question, int total, String xp) {
    return 'რაუნდი შენახულია (კითხვა $question / $total, $xp XP). გააგრძელე მთავარი გვერდიდან.';
  }

  @override
  String get quizLeaveKeepPlaying => 'თამაშის გაგრძელება';

  @override
  String get quizLeaveConfirm => 'ახლა გასვლა';

  @override
  String get toastPinOutsideArea =>
      'შენი ქუჩა წრის შიგნითაა. აქაც შეგიძლია დაადასტურო.';

  @override
  String get toastOffline =>
      'ინტერნეტი არ გაქვს. რუკაზე ხარვეზებია, მაგრამ რაუნდი გრძელდება.';

  @override
  String toastRoundResumed(int question) {
    return 'კეთილი იყოს შენი დაბრუნება. რაუნდი გრძელდება: კითხვა $question.';
  }

  @override
  String get tierPerfect => 'იდეალურია!';

  @override
  String get tierGreat => 'შესანიშნავია!';

  @override
  String get tierClose => 'ახლოს';

  @override
  String get tierMiss => 'ამჯერად ვერა';

  @override
  String get tierPerfectWord => 'იდეალური';

  @override
  String get tierGreatWord => 'შესანიშნავი';

  @override
  String get tierMissWord => 'აცდენა';

  @override
  String get tierPerfectSentence => 'ზუსტად ქუჩაზე. ეს ქალაქი კარგად იცი.';

  @override
  String tierGreatSentence(String distance) {
    return 'დაშორება: $distance. იდეალურთან ძალიან ახლოს.';
  }

  @override
  String tierCloseSentence(String distance) {
    return 'დაშორება: $distance. სწორ უბანში ხარ.';
  }

  @override
  String tierMissSentence(String distance, String hint) {
    return 'დაშორება: $distance. $hint შედეგებში კიდევ შეხვდები.';
  }

  @override
  String revealStreak(int count) {
    return '$count ზედიზედ';
  }

  @override
  String get revealGotIt => 'გასაგებია';

  @override
  String get revealSeeResults => 'შედეგების ნახვა';

  @override
  String get resultsTitle => 'რაუნდი დასრულდა!';

  @override
  String get resultsFlawless => 'უნაკლო რაუნდი!';

  @override
  String get resultsRetryTitle => 'გამეორება დასრულდა';

  @override
  String resultsStreetsKnown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count ნაცნობი ქუჩა',
    );
    return '$_temp0';
  }

  @override
  String get resultsYourStreets => 'შენი ქუჩები';

  @override
  String resultsRetryMissed(int count) {
    return 'გაიმეორე $count შეცდომა';
  }

  @override
  String get resultsNoRetry => 'გასამეორებელი არაფერია';

  @override
  String get resultsToRetry => 'გასამეორებელი';

  @override
  String get resultsOnStreet => 'ქუჩაზე';

  @override
  String get resultsPlayAgain => 'ახლიდან თამაში';

  @override
  String get resultsNewRound => 'ახალი რაუნდი';

  @override
  String levelUpTitle(int level) {
    return 'დონე $level!';
  }

  @override
  String levelUpBody(String xp) {
    return 'სულ $xp XP. აქამდე ყოველმა კარგმა პასუხმა მოგიყვანა.';
  }

  @override
  String levelUpNext(int level) {
    return 'შემდეგი: დონე $level';
  }

  @override
  String get settingsTitle => 'პარამეტრები';

  @override
  String get settingsLanguage => 'ენა';

  @override
  String get settingsAppLanguage => 'აპის ენა';

  @override
  String get settingsStreetNames => 'ქუჩების სახელები';

  @override
  String get settingsStreetNamesLocal => 'ადგილობრივი';

  @override
  String get settingsStreetNamesEnglish => 'ინგლისური';

  @override
  String get settingsStreetNamesHelp =>
      'ინგლისური ჩანს, თუ რუკაზეა, თორემ ადგილობრივი სახელი.';

  @override
  String get settingsDisplay => 'ეკრანი და უკუკავშირი';

  @override
  String get settingsTheme => 'თემა';

  @override
  String get settingsThemeLight => 'ღია';

  @override
  String get settingsThemeDark => 'მუქი';

  @override
  String get settingsThemeSystem => 'სისტემური';

  @override
  String get settingsSound => 'ხმა';

  @override
  String get settingsSoundSubtitle => 'ზარები, შეხებები და ზეიმი';

  @override
  String get settingsHaptics => 'ვიბრაცია';

  @override
  String get settingsHapticsSubtitle => 'ვიბრაცია მონიშვნისას და პასუხებზე';

  @override
  String get settingsAbout => 'აპის შესახებ';

  @override
  String get creditsTitle => 'რუკის მონაცემების წყაროები';

  @override
  String get creditsIntro =>
      'პინდორო ღია რუკის მონაცემებზეა აგებული. მადლობა ყველას, ვინც საკუთარ ქუჩებს რუკაზე ასახავს.';

  @override
  String get creditsFix =>
      'შენიშნე გამოტოვებული ან არასწორი ქუჩა? გაასწორე openstreetmap.org-ზე და პინდორო რამდენიმე კვირაში განახლდება.';

  @override
  String get creditsOsm => '© OpenStreetMap contributors';

  @override
  String get creditsOsmLicence =>
      'რუკის მონაცემების ლიცენზია: Open Database License (ODbL).';

  @override
  String get creditsOsmLink => 'openstreetmap.org/copyright';

  @override
  String get creditsTiles => 'რუკის ფილები: Protomaps';

  @override
  String get creditsFont => 'შრიფტი: FiraGO (SIL Open Font License)';

  @override
  String get a11yLeaveRound => 'რაუნდიდან გასვლა';

  @override
  String a11yFindStreet(String name, String altName) {
    return 'იპოვე: $name, $altName';
  }

  @override
  String get a11yMap => 'რუკა. ცენტრში მოსანიშნად ორჯერ შეეხე.';

  @override
  String get a11yPin => 'შენი ნიშნული. გადასატანად ორჯერ შეეხე და დააჭირე.';

  @override
  String get a11yConfirmDisabled => 'დადასტურება. ჯერ მონიშნე რუკაზე.';

  @override
  String a11yReveal(String tier, String distance, String xp) {
    return '$tier. დაშორება: $distance. +$xp XP.';
  }

  @override
  String a11yLevelProgress(int level, String xp, String xpNeeded) {
    return 'დონე $level, $xp / $xpNeeded XP';
  }

  @override
  String get a11yGoToMyLocation => 'ჩემს მდებარეობაზე გადასვლა';

  @override
  String get a11yRecentre => 'ცენტრში დაბრუნება';

  @override
  String get a11yZoomIn => 'გადიდება';

  @override
  String get a11yZoomOut => 'დაპატარავება';

  @override
  String revealMissDirection(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'n': 'ქუჩა შენი ნიშნულის ჩრდილოეთითაა.',
      'ne': 'ქუჩა შენი ნიშნულის ჩრდილო-აღმოსავლეთითაა.',
      'e': 'ქუჩა შენი ნიშნულის აღმოსავლეთითაა.',
      'se': 'ქუჩა შენი ნიშნულის სამხრეთ-აღმოსავლეთითაა.',
      's': 'ქუჩა შენი ნიშნულის სამხრეთითაა.',
      'sw': 'ქუჩა შენი ნიშნულის სამხრეთ-დასავლეთითაა.',
      'w': 'ქუჩა შენი ნიშნულის დასავლეთითაა.',
      'nw': 'ქუჩა შენი ნიშნულის ჩრდილო-დასავლეთითაა.',
      'other': 'ქუჩა შენს ნიშნულთან ახლოსაა.',
    });
    return '$_temp0';
  }

  @override
  String a11yFindStreetName(String name) {
    return 'იპოვე: $name';
  }

  @override
  String a11yRoundXp(String xp) {
    return 'ამ რაუნდში $xp XP';
  }

  @override
  String a11yResultRow(
    int question,
    String street,
    String tier,
    String distance,
    String xp,
  ) {
    return 'კითხვა $question. $street. $tier, $distance, +$xp XP. რუკაზე ნახვა.';
  }

  @override
  String get resultsPreviousStreet => 'წინა';

  @override
  String get resultsNextStreet => 'შემდეგი ქუჩა';

  @override
  String get resultsBackToResults => 'შედეგებზე დაბრუნება';

  @override
  String a11yRewardTotal(String xp) {
    return 'ამ რაუნდში +$xp XP';
  }

  @override
  String a11yTierTally(int perfect, int great, int close, int miss) {
    return '$perfect იდეალური, $great შესანიშნავი, $close ახლოს, $miss აცდენა';
  }

  @override
  String setupSparseCount(int count, String difficulty) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ამ არეალში $difficulty დონეზე $count ქუჩაა.',
    );
    return '$_temp0';
  }

  @override
  String get setupAreaMissingBody =>
      'ამ არეალის ქუჩები ჯერ ტელეფონზე არ გაქვს. აირჩიე არეალი იმათგან, რაც გაქვს.';

  @override
  String areaCircleName(String size) {
    return '$size წრე';
  }

  @override
  String areaRectangleName(String size) {
    return '$size მართკუთხედი';
  }

  @override
  String difficultyScoringTitle(String difficulty) {
    return 'რამდენად ახლოს უნდა იყო: $difficulty';
  }

  @override
  String difficultyWithin(String distance) {
    return '$distance-ის ფარგლებში';
  }

  @override
  String get cityNoneNearby =>
      'შენს ახლოს ქალაქი ჯერ არ გვაქვს. აირჩიე სიიდან.';

  @override
  String get cityAll => 'ყველა ქალაქი';

  @override
  String get cityClearSearch => 'ძებნის გასუფთავება';

  @override
  String a11yCitySwitcher(String city) {
    return 'ქალაქი: $city. ქალაქის შეცვლა.';
  }

  @override
  String a11yPlay(String what) {
    return 'თამაში: $what';
  }

  @override
  String get a11ySettings => 'პარამეტრები';

  @override
  String homeXpTotalShort(String xp) {
    return '$xp XP';
  }

  @override
  String homeKnownOf(String known, String total) {
    return '$known / $total';
  }

  @override
  String homeSavedProgress(int question, int total, String xp) {
    return 'კითხვა $question / $total · ჯერჯერობით $xp XP';
  }

  @override
  String unitMinutes(int count) {
    return '$count წთ';
  }

  @override
  String unitHours(int count) {
    return '$count სთ';
  }

  @override
  String unitDays(int count) {
    return '$count დღე';
  }
}
