/// Paths from docs/design/v1-screens.md § Navigation.
abstract final class Routes {
  /// Explore, the second tab: Free play on any area.
  static const String home = '/';
  static const String welcome = '/welcome';
  static const String city = '/city';

  /// The city picker of a new player: a city leads on to Today (placement)
  /// instead of the area picker.
  static const String cityToLearn = '$city?learn=1';
  static const String area = '/area';
  static const String difficulty = '/difficulty';

  /// `?round=<id>` resumes, `?retry=<id>` plays that round's missed streets.
  static const String round = '/round';

  /// `?round=<id>`; `/results/street/<index>?round=<id>` opens one answer.
  static const String results = '/results';
  static const String streak = '/streak';
  static const String me = '/me';

  /// Signing in, creating an account or a new password (Settings → Account).
  static const String account = '/account';

  /// Settings → Account → Change password.
  static const String accountPassword = '/account/password';
  static const String settings = '/settings';

  /// Today's session, City memory and placement: the first tab.
  static const String today = '/today';

  /// Today's learning session (SessionScreen); `?placement=1` places,
  /// `?more=1` learns 5 more.
  static const String session = '/session';
  static const String placement = '$session?placement=1';

  /// "Learn 5 more": five new streets past the daily number.
  static const String learnMore = '$session?more=1';
  static const String credits = '/settings/credits';

  /// City memory, recall, the forecast and the districts: the third tab.
  static const String progress = '/progress';

  /// `?id=<raion id>`: a district's neighbourhoods.
  static const String progressDistrict = '/progress/district';

  /// Minutes a day, home and work, street names, the reminder.
  static const String learnSettings = '/settings/learning';

  /// `?which=home|work`: the neighbourhood picker for an anchor.
  static const String anchor = '/settings/learning/anchor';

  /// The player's own landmarks, and adding one on the map.
  static const String landmarks = '/settings/learning/landmarks';
  static const String landmarkAdd = '/settings/learning/landmarks/add';

  /// A GPS-free drive: setup, recording and review (DriveScreen).
  static const String drive = '/drive';

  static String progressOf(String districtId) =>
      '$progressDistrict?id=$districtId';
  static String anchorOf(String which) => '$anchor?which=$which';

  /// The area picker starting from one district (nothing saved until Next).
  static String areaFrom(String districtId) => '$area?district=$districtId';
  static String resume(String roundId) => '$round?round=$roundId';
  static String retry(String roundId) => '$round?retry=$roundId';
  static String resultsOf(String roundId) => '$results?round=$roundId';
  static String resultStreet(String roundId, int index) =>
      '$results/street/$index?round=$roundId';
}

/// What a finished round changed, for Home's one-time intro (canvas M-43). Results passes it to
/// [Routes.home] as the route's `extra`.
typedef RoundSummary = ({String roundId, DateTime startedAt});
