import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';

void main() {
  for (final theme in ['light', 'dark']) {
    test(
      'every landmark kind in the $theme style has an icon, and no more',
      () {
        final style =
            jsonDecode(
                  File(
                    'assets/map_styles/pindoro_$theme.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        final pois = (style['layers']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((l) => l['id'] == 'pois');
        // filter: ["all", ["in", ["get", "kind"], ["literal", [kinds…]]], …]
        final kinds =
            (((pois['filter']! as List)[1] as List)[2] as List)[1] as List;
        expect(kinds.toSet(), poiIcons.keys.toSet());
      },
    );
  }

  test('every icon is a bundled Maki SVG', () {
    for (final (icon, _) in poiIcons.values) {
      expect(
        File(
          '../../packages/pindoro_design/assets/map_icons/$icon.svg',
        ).existsSync(),
        isTrue,
        reason: icon,
      );
    }
  });
}
