import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

const _at = LatLng(41.69, 44.70);

NamedStreet _street(String id, String chunk) => NamedStreet([
  Street(
    id: id,
    nameKa: 'შოთა რუსთაველის ქუჩა',
    nameEn: 'Shota Rustaveli Street',
    roadClass: 'secondary',
    difficulty: Difficulty.medium,
    lengthM: 900,
    midpoint: _at,
    bbox: const Bbox(41.69, 44.70, 41.69, 44.70),
    geometry: const [
      [_at, _at],
    ],
    chunkId: chunk,
  ),
]);

const _tskneti = District(
  id: 'tskneti',
  kind: DistrictKind.neighbourhood,
  osmRelationId: null,
  nameKa: 'წყნეთი',
  nameEn: 'Tskneti',
  center: _at,
  bbox: Bbox(41.69, 44.70, 41.69, 44.70),
  areaM2: 1e6,
  boundary: [],
);

void main() {
  final shared = _street('shared', 'tskneti');
  final own = _street('own', 'vake');

  Future<void> pump(WidgetTester tester, NamedStreet street) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            namesakeAreaProvider.overrideWith(
              (ref) async =>
                  (s) => s == shared ? _tskneti : null,
            ),
          ],
          child: MaterialApp(
            theme: buildPindoroTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: QuestionPlate(
                street: street,
                settings: null,
                compact: false,
              ),
            ),
          ),
        ),
      );

  testWidgets('a shared name shows its area on the sub-line', (tester) async {
    await pump(tester, shared);
    await tester.pump();
    expect(find.text('Shota Rustaveli Street · წყნეთი'), findsOneWidget);
  });

  testWidgets('a name of its own shows only its other script', (tester) async {
    await pump(tester, own);
    await tester.pump();
    expect(find.text('Shota Rustaveli Street'), findsOneWidget);
  });
}
