import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late SqlitePackRepository pack;

  setUpAll(() => pack = SqlitePackRepository.open(AppConfig.fixturePackAsset));
  tearDownAll(() => pack.close());

  test('meta describes a v5 fixture pack with attribution', () {
    final meta = pack.meta();
    expect(meta['format_version'], '5');
    expect(meta['scope'], 'fixture');
    expect(meta['version'], isNotEmpty);
    expect(meta['attribution'], contains('OpenStreetMap'));
  });

  test('format 5 adds the junction items, their landmarks and the junctions\' '
      'OSM nodes', () {
    final items = pack.junctionItems();
    expect(items, isNotEmpty);
    expect(
      items.map((i) => i.rank),
      orderedEquals([...items.map((i) => i.rank)]..sort()),
    );
    final nodes = pack.junctionNodes();
    expect(items.every((i) => nodes.containsKey(i.junctionId)), isTrue);
    final landmarks = {for (final l in pack.landmarks()) l.id};
    expect(
      items
          .where((i) => i.landmarkId != null)
          .every((i) => landmarks.contains(i.landmarkId)),
      isTrue,
    );
  });

  test('the fixture holds Vake and the quarters and neighbourhoods in it', () {
    expect(pack.city().id, 'tbilisi');
    final districts = pack.districts();
    expect(districts.where((d) => d.isRaion).map((d) => d.id), [
      AppConfig.fixtureDistrictId,
    ]);
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

  test('the road graph joins the fixture streets at junctions', () {
    final graph = pack.roadGraph()!;
    final parts = {for (final s in pack.streets()) s.id};
    expect(graph.edges, isNotEmpty);
    expect(
      graph.edges.every(
        (e) => e.streetId == null || parts.contains(e.streetId),
      ),
      isTrue,
      reason: 'an edge is a street part or a connector',
    );
    final edge = graph.edges.first;
    expect(edge.line.first.lat, closeTo(graph.at(edge.from).lat, 1e-5));
    expect(edge.line.last.lon, closeTo(graph.at(edge.to).lon, 1e-5));
    final far = graph.junctions.keys.last;
    final route = graph.shortestRoute(graph.junctions.keys.first, {far});
    expect(route == null || route.lengthM > 0, isTrue);
  });

  test('curriculum data: tiers, rings, banks, chunks, raions and families', () {
    final streets = pack.streets();
    expect(streets.every((s) => s.tier != null && s.ring != null), isTrue);
    expect(streets.map((s) => s.bank).toSet(), {RiverBank.right});
    final chunks = {
      for (final d in pack.districts())
        if (d.kind == DistrictKind.neighbourhood) d.id: d,
    };
    expect(chunks.values.every((d) => d.parentId != null), isTrue);
    expect(
      streets.map((s) => s.chunkId).nonNulls.every(chunks.containsKey),
      isTrue,
    );
    for (final MapEntry(:key, :value) in pack.chunkNeighbours().entries) {
      expect(chunks.containsKey(key), isTrue);
      expect(value.every(chunks.containsKey), isTrue);
    }
    final ids = {for (final s in streets) s.id};
    final families = pack.families();
    expect(families, isNotEmpty);
    expect(
      families.every(
        (f) => ids.contains(f.parentId) && ids.contains(f.childId),
      ),
      isTrue,
    );
  });
}
