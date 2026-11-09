import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late SqlitePackRepository pack;

  setUpAll(() => pack = SqlitePackRepository.open(AppConfig.fixturePackAsset));
  tearDownAll(() => pack.close());

  test('meta describes a v2 fixture pack with attribution', () {
    final meta = pack.meta();
    expect(meta['format_version'], '2');
    expect(meta['scope'], 'fixture');
    expect(meta['version'], isNotEmpty);
    expect(meta['attribution'], contains('OpenStreetMap'));
  });

  test('the fixture holds Vake and the quarters and neighbourhoods in it', () {
    expect(pack.city().id, 'tbilisi');
    final districts = pack.districts();
    expect(
      districts.where((d) => d.kind == DistrictKind.district).map((d) => d.id),
      [AppConfig.fixtureDistrictId],
    );
    expect(
      districts.map((d) => d.kind),
      containsAll([DistrictKind.quarter, DistrictKind.neighbourhood]),
    );
  });

  test('district streets decode and lie inside the city bbox', () {
    final city = pack.city();
    final streets = pack.streets(districtId: AppConfig.fixtureDistrictId);
    expect(streets, isNotEmpty);
    for (final s in streets) {
      expect(s.geometry, isNotEmpty);
      expect(s.geometry.every((part) => part.length >= 2), isTrue);
      expect(city.bbox.clamp(s.midpoint), s.midpoint, reason: s.id);
    }
  });

  test('has at least 30 expert streets in the fixture district', () {
    final expert = pack.streets(
      districtId: AppConfig.fixtureDistrictId,
      difficulties: {Difficulty.expert},
    );
    expect(expert.length, greaterThanOrEqualTo(30));
    expect(expert.every((s) => s.difficulty == Difficulty.expert), isTrue);
  });

  test('partsByDistrict lists the district streets', () {
    final streets = pack.streets(districtId: AppConfig.fixtureDistrictId);
    expect(pack.partsByDistrict()[AppConfig.fixtureDistrictId], {
      for (final s in streets) s.id,
    });
  });

  test('lengthsByDistrict measures each part inside its districts', () {
    final lengths = pack.lengthsByDistrict()[AppConfig.fixtureDistrictId]!;
    expect(
      lengths.keys.toSet(),
      pack.partsByDistrict()[AppConfig.fixtureDistrictId],
    );
    for (final s in pack.streets(districtId: AppConfig.fixtureDistrictId)) {
      expect(lengths[s.id], inInclusiveRange(0, s.lengthM + 1));
    }
  });
}
