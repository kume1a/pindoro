/// Paths from docs/design/v1-screens.md § Navigation.
abstract final class Routes {
  static const String home = '/';
  static const String welcome = '/welcome';
  static const String city = '/city';
  static const String area = '/area';
  static const String difficulty = '/difficulty';

  /// `?round=<id>` resumes, `?retry=<id>` plays that round's missed streets.
  static const String round = '/round';

  /// `?round=<id>`; `/results/street/<index>?round=<id>` opens one answer.
  static const String results = '/results';
  static const String streak = '/streak';
  static const String pitStop = '/pit-stop';

  /// The Pit stop's due streets as a round.
  static const String pitStopRound = '$round?pit-stop=1';
  static const String me = '/me';
  static const String settings = '/settings';
  static const String credits = '/settings/credits';

  /// The course, the first tab.
  static const String path = '/path';

  /// `?unit=<raion id>&lesson=<n>` (`&practice=1` replays its test) or
  /// `?unit=<raion id>&pit-stop=1`.
  static const String lesson = '/lesson';

  /// `?result=<lesson result id>`.
  static const String lessonDone = '/lesson-done';

  /// The area picker starting from one district (nothing saved until Next).
  static String areaFrom(String districtId) => '$area?district=$districtId';
  static String resume(String roundId) => '$round?round=$roundId';
  static String retry(String roundId) => '$round?retry=$roundId';
  static String resultsOf(String roundId) => '$results?round=$roundId';
  static String resultStreet(String roundId, int index) =>
      '$results/street/$index?round=$roundId';
  static String lessonOf(String unitId, int n, {bool practice = false}) =>
      '$lesson?unit=$unitId&lesson=$n${practice ? '&practice=1' : ''}';
  static String unitPitStop(String unitId) => '$lesson?unit=$unitId&pit-stop=1';
  static String lessonDoneOf(String resultId) => '$lessonDone?result=$resultId';
}

/// What a finished round changed, for Home's one-time intro (canvas M-43). Results passes it to
/// [Routes.home] as the route's `extra`.
typedef RoundSummary = ({String roundId, DateTime startedAt, int roundXp});
