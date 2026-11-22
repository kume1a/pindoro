import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

part 'drive_log.g.dart';

/// The drive log (SPEC §16.23 item 124): every drive's summary for good, its track for
/// [LearningConfig.driveTrackKeepDays].
@DriftAccessor(tables: [Drives, DriveTracks, DriveDecisions, DriveEvents])
class DriveLogDao extends DatabaseAccessor<AppDatabase>
    with _$DriveLogDaoMixin {
  DriveLogDao(super.attachedDatabase);

  /// Saves [drive] with its [track] and [decisions], and drops the tracks of drives that ended
  /// more than [LearningConfig.driveTrackKeepDays] before it.
  Future<void> save(
    DriveRow drive,
    String track, {
    List<DriveDecisionRow> decisions = const [],
  }) => transaction(() async {
    await into(drives).insert(drive);
    await batch((b) => b.insertAll(driveDecisions, decisions));
    await into(
      driveTracks,
    ).insert(DriveTracksCompanion.insert(driveId: drive.id, track: track));
    final keepFrom = drive.endedAt.subtract(
      const Duration(days: LearningConfig.driveTrackKeepDays),
    );
    final old = selectOnly(drives)
      ..addColumns([drives.id])
      ..where(drives.endedAt.isSmallerThanValue(keepFrom));
    await (delete(driveTracks)..where((t) => t.driveId.isInQuery(old))).go();
  });

  /// Every drive, the latest first.
  Future<List<DriveRow>> all() =>
      (select(drives)..orderBy([(d) => OrderingTerm.desc(d.startedAt)])).get();

  Future<DriveRow?> drive(String id) =>
      (select(drives)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// The drive's fixes, or null once its track is gone.
  Future<List<DriveFix>?> track(String id) async {
    final row = await (select(
      driveTracks,
    )..where((t) => t.driveId.equals(id))).getSingleOrNull();
    return row == null ? null : decodeTrack(row.track);
  }

  /// Every logged decision of every drive.
  Future<List<DriveDecisionRow>> decisions() => select(driveDecisions).get();

  /// [driveId]'s decisions in drive order.
  Future<List<DriveDecisionRow>> decisionsOf(String driveId) =>
      (select(driveDecisions)
            ..where((d) => d.driveId.equals(driveId))
            ..orderBy([(d) => OrderingTerm.asc(d.seq)]))
          .get();

  /// Appends a preview, recital, debrief or pointing result (SPEC §16.23 item 124).
  Future<void> addEvent({
    required String driveId,
    required DateTime at,
    required DriveEventKind kind,
    String? itemKey,
    double? value,
  }) => into(driveEvents).insert(
    DriveEventsCompanion.insert(
      driveId: driveId,
      at: at,
      kind: kind,
      itemKey: Value(itemKey),
      value: Value(value),
    ),
  );

  /// Every event of [kind], oldest first.
  Future<List<DriveEventRow>> events(DriveEventKind kind) =>
      (select(driveEvents)
            ..where((e) => e.kind.equalsValue(kind))
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  /// The ids of the drives whose track is still kept.
  Future<Set<String>> tracked() async {
    final ids = selectOnly(driveTracks)..addColumns([driveTracks.driveId]);
    return {for (final row in await ids.get()) row.read(driveTracks.driveId)!};
  }
}

final driveLogDaoProvider = Provider<DriveLogDao>(
  (ref) => DriveLogDao(ref.watch(databaseProvider)),
);

/// Every drive, the latest first, with whether its track is still kept (Past drives, board
/// V32-60). Saving a drive invalidates it.
final pastDrivesProvider =
    FutureProvider.autoDispose<List<({DriveRow drive, bool tracked})>>((
      ref,
    ) async {
      final dao = ref.watch(driveLogDaoProvider);
      final tracked = await dao.tracked();
      return [
        for (final d in await dao.all())
          (drive: d, tracked: tracked.contains(d.id)),
      ];
    });
