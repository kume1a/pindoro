/// Build-time configuration via `--dart-define`. Dev defaults reach the host
/// machine from the Android emulator (10.0.2.2).
abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  static const String tilesBaseUrl = String.fromEnvironment(
    'TILES_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  /// The city played before one is chosen; the bundled fixture's city.
  static const String defaultCityId = 'tbilisi';

  static const String fixturePackAsset =
      'assets/packs_fixture/tbilisi_vake_fixture.sqlite';
  static const String fixtureDistrictId = 'osm:r11300449';
}
