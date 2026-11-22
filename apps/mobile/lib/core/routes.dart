/// Paths from docs/design/v1-screens.md § Navigation.
abstract final class Routes {
  /// Explore, the second tab: Free play on any area.
  static const String home = '/';
  static const String welcome = '/welcome';
  static const String area = '/area';
  static const String difficulty = '/difficulty';

  /// `?round=<id>` resumes, `?retry=<id>` plays that round's missed streets.
  static const String round = '/round';

  /// "Your streets": a round of streets the player has learned.
  static const String yourStreets = '$round?learned=1';

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
  /// `?more=1` learns 10 more.
  static const String session = '/session';
  static const String placement = '$session?placement=1';

  /// "Learn 10 more": ten new streets past the daily number.
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

  /// Calibration, fitted FSRS weights and tier C relief (SPEC §12).
  static const String memoryModel = '/settings/learning/memory';

  /// The Drive tab, the first tab and the page the app opens on: Where to, Home and Work.
  static const String driveTab = '/drive';

  /// A drive: setup, recording and debrief (DriveScreen); `?to=home|work|run|surprise` opens on
  /// that destination, a street or place comes as the route's `extra`.
  static const String drive = '/drive/go';
  static const String driveRun = '$drive?to=run';

  static String driveTo(String to) => '$drive?to=$to';

  /// A destination picked on the map; `?place=1` for Home or Work. Pops with a `DriveDest`.
  static const String driveMap = '/drive/map';
  static const String driveMapPlace = '$driveMap?place=1';

  /// Home or Work for drives (`?which=home|work`).
  static const String drivePlace = '/drive/place';

  static String drivePlaceOf(String which) => '$drivePlace?which=$which';

  /// The route preview of the drive being set up (V32-11).
  static const String drivePreview = '/drive/preview';

  /// Every drive by week (`?route=`: one route's), and one of them (`?id=`): its debrief.
  static const String pastDrives = '/drive/past';
  static const String pastDrive = '/drive/past/one';

  static String pastDrivesOf(String route) =>
      Uri(path: pastDrives, queryParameters: {'route': route}).toString();

  static String pastDriveOf(String id) => '$pastDrive?id=$id';

  /// A short session of [items] as relearns (a drive's missed turns).
  static String drillOf(List<String> items) => Uri(
    path: session,
    queryParameters: {'drill': items.join(' ')},
  ).toString();

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
