import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const line = [LatLng(41.7, 44.8), LatLng(41.71, 44.8)];
  final street = NamedStreet([
    Street(
      id: 's',
      nameKa: 'ქუჩა',
      nameEn: null,
      roadClass: 'residential',
      difficulty: Difficulty.easy,
      lengthM: 1110,
      midpoint: const LatLng(41.705, 44.8),
      bbox: Bbox.of(line),
      geometry: const [line],
    ),
  ]);

  test('Street View opens a panorama at the spot, looking its way', () {
    final link = GoogleMaps.streetView((
      at: const LatLng(41.7, 44.8),
      heading: 89.6,
    ));
    expect(link.host, 'www.google.com');
    expect(link.queryParameters, {
      'api': '1',
      'map_action': 'pano',
      'viewpoint': '41.7,44.8',
      'heading': '90',
    });
  });

  test('a street spot looks along the street, a place spot at the place', () {
    final along = streetSpot(street, const LatLng(41.705, 44.801));
    expect(along.at.lon, closeTo(44.8, 1e-9));
    expect(along.heading, closeTo(0, 0.1));
    final shop = placeSpot(street, const LatLng(41.705, 44.801));
    expect(shop.heading, closeTo(90, 0.5));
  });
}
