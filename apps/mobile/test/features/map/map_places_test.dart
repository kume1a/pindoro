import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/map/data/map_places.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  test("a tile's feature id is its OSM object", () {
    expect(osmIdOf((1 << 44) + 123), 'osm:n123');
    expect(osmIdOf('${(2 << 44) + 45}'), 'osm:w45');
    expect(osmIdOf(((3 << 44) + 6).toDouble()), 'osm:r6');
    expect(osmIdOf(123), isNull, reason: 'no type');
    expect(osmIdOf(null), isNull);
  });

  test('the place tapped is the feature nearest the finger', () {
    const near = LatLng(41.7, 44.77);
    Map<String, Object?> feature(int id, double lat, String name) => {
      'type': 'Feature',
      'id': (1 << 44) + id,
      'geometry': {
        'type': 'Point',
        'coordinates': [44.77, lat],
      },
      'properties': {'kind': 'cafe', 'name': name},
    };
    final place = mapPlaceAt([
      feature(1, 41.7003, 'Far'),
      feature(2, 41.7001, 'Near'),
      {'geometry': null},
    ], near);
    expect(place?.id, 'osm:n2');
    expect(place?.name, 'Near');
    expect(place?.kind, 'cafe');
    expect(mapPlaceAt(const [], near), isNull);
  });

  test("a place's phone and website as links", () {
    expect(
      phoneLink('+995 32 200-00-00; +995 555 00')?.toString(),
      'tel:+995322000000',
    );
    expect(phoneLink(' '), isNull);
    expect(webLink('example.ge')?.toString(), 'https://example.ge');
    expect(webLink('http://a.ge;https://b.ge')?.toString(), 'http://a.ge');
    expect(webLink(null), isNull);
  });
}
