import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';

export 'package:pindoro/core/database/database.dart' show PersonalLandmarkRow;

/// The kinds a player gives their own landmarks (SPEC §9, board V3-32).
const List<String> personalLandmarkKinds = [
  'fuel',
  'metro',
  'worship',
  'shop',
  'other',
];

/// The player's own landmarks, newest first; writers invalidate it.
final personalLandmarksProvider =
    FutureProvider.autoDispose<List<PersonalLandmarkRow>>(
      (ref) => ref.watch(learningDaoProvider).personalLandmarks(),
    );

/// A new landmark: `me:<uuidv7>`, [junctionNode] and [approachNode] the OSM
/// node ids of the snapped junction and of its neighbour along the approach.
PersonalLandmarkRow newPersonalLandmark({
  required String name,
  required String kind,
  required double lat,
  required double lon,
  required int junctionNode,
  required int approachNode,
  required bool onLeft,
  required DateTime now,
}) => PersonalLandmarkRow(
  id: 'me:${newId()}',
  name: name.trim(),
  kind: kind,
  lat: lat,
  lon: lon,
  junctionId: 'n$junctionNode',
  approachEdgeId: 'n$approachNode',
  side: onLeft ? 'left' : 'right',
  createdAt: now,
);
