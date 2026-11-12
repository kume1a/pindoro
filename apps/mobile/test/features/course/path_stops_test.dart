import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/course/ui/path_stops.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  CourseStop lesson(int n, StopState state) =>
      (kind: StopKind.lesson, lesson: n, state: state);

  UnitProgress unit(List<CourseStop> stops) => (
    unit: const CourseUnit(
      number: 1,
      district: District(
        id: 'osm:r1',
        kind: DistrictKind.district,
        osmRelationId: 1,
        nameKa: 'ვაკე',
        nameEn: 'Vake',
        center: LatLng(41.7, 44.75),
        bbox: Bbox(41.7, 44.75, 41.7, 44.75),
        areaM2: 1,
        boundary: [],
      ),
      lessons: [],
    ),
    open: true,
    done: false,
    stops: stops,
    lessonsDone: stops.where((s) => s.done).length,
    tripsPassed: 0,
  );

  group('a locked stop', () {
    test('names the stop just before it to finish', () {
      final units = [
        unit([
          lesson(1, StopState.done),
          lesson(2, StopState.current),
          lesson(3, StopState.locked),
        ]),
      ];
      expect(lockedNote(l10n, units, 0, 2, null), (
        title: l10n.pathLockedLesson(3),
        body: l10n.pathFinishLesson(2),
      ));
    });

    test('names the current stop when placement marked a later one done', () {
      final units = [
        unit([
          lesson(1, StopState.current),
          lesson(2, StopState.done),
          lesson(3, StopState.locked),
        ]),
      ];
      expect(
        lockedNote(l10n, units, 0, 2, null)?.body,
        l10n.pathFinishLesson(1),
      );
    });

    test('an open stop has no note', () {
      final units = [
        unit([lesson(1, StopState.current)]),
      ];
      expect(lockedNote(l10n, units, 0, 0, null), isNull);
    });
  });

  group('the unlock paves', () {
    test('to the next stop', () {
      expect(pavedTo(done: 0, next: 1, driven: 2, t: 0.5), 1.5);
    });

    test('past stops already done, up to the one that opens', () {
      expect(pavedTo(done: 2, next: 4, driven: 5, t: 0), 3);
      expect(pavedTo(done: 2, next: 4, driven: 5, t: 0.5), 4);
      expect(pavedTo(done: 2, next: 4, driven: 5, t: 1), 5);
    });

    test('never back from asphalt that already reached further', () {
      expect(pavedTo(done: 0, next: 1, driven: 5, t: 0.5), 5);
    });
  });
}
