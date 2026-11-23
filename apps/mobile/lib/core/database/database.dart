import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.steps.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

String newId() => const Uuid().v7();

/// Parses a stored area; null when unset or unreadable (e.g. the M1 whole city).
Area? parseArea(String? json) {
  if (json == null) return null;
  try {
    return switch (jsonDecode(json)) {
      final Map<String, Object?> map => Area.fromJson(map),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

extension SettingsArea on Settings {
  /// The saved area; null until the player picks one.
  Area? get area => parseArea(lastAreaJson);

  /// The saved difficulty; medium (the picker's default) until one is picked.
  Difficulty get difficulty => lastDifficulty ?? Difficulty.medium;

  /// The chosen city; the default one until the player picks.
  String get cityId => lastCity ?? AppConfig.defaultCityId;
}

enum AppLanguage { en, ka }

/// How street names show: as the city writes them, or in English when the
/// pack has an English name.
enum StreetNameMode { local, english }

/// Light, dark, or the device setting (kept Flutter-free for drift's exporter).
enum ThemePreference { system, light, dark }

/// The car on Guided's map: a navigation arrow or the car disc.
enum DriveMarker { arrow, car }

/// Single row (id = 1) of local preferences.
@DataClassName('Settings')
class UserSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get lastCity => text().nullable()();
  TextColumn get lastAreaJson => text().nullable()();
  TextColumn get lastDifficulty => textEnum<Difficulty>().nullable()();

  /// Null follows the device language.
  TextColumn get appLanguage => textEnum<AppLanguage>().nullable()();
  // Literal defaults: drift copies them into the generated migration steps.
  TextColumn get streetNames =>
      textEnum<StreetNameMode>().withDefault(const Constant('local'))();
  TextColumn get theme =>
      textEnum<ThemePreference>().withDefault(const Constant('system'))();
  BoolColumn get sound => boolean().withDefault(const Constant(true))();
  BoolColumn get haptics => boolean().withDefault(const Constant(true))();

  /// The first Home's coach mark was closed.
  BoolColumn get homeCoachSeen =>
      boolean().withDefault(const Constant(false))();

  /// The 19:00 reminder when today's day hasn't counted and reviews are due.
  BoolColumn get reminder => boolean().withDefault(const Constant(false))();

  /// The daily learning session's length: 15, 20 or 30 minutes.
  IntColumn get minutesPerDay => integer().withDefault(const Constant(20))();

  /// FSRS weights fitted to this player's log (`just fsrs-fit`), as JSON;
  /// null runs SPEC §4's. Read at launch.
  TextColumn get fsrsWeights => text().nullable()();

  /// The maps' zoom in and out buttons (pinch zooms either way).
  BoolColumn get zoomButtons => boolean().withDefault(const Constant(false))();

  /// "Warn me over the limit by", km/h (SPEC §16.23 item 127; `speedToleranceKmh`).
  IntColumn get speedToleranceKmh =>
      integer().withDefault(const Constant(14))();

  /// Home and Work for drives (SPEC §16.23 item 120), as JSON (`DrivePlace`); null until set.
  TextColumn get driveHome => text().nullable()();
  TextColumn get driveWork => text().nullable()();

  /// This week's planned drives (item 122, "Pick your two drives"), as JSON (`DrivePlan`); null
  /// until the first plan.
  TextColumn get drivePlan => text().nullable()();

  /// The car on Guided's map (SPEC §16.23 item 130).
  TextColumn get driveMarker =>
      textEnum<DriveMarker>().withDefault(const Constant('arrow'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Round')
class Rounds extends Table {
  @override
  String get tableName => 'round';

  TextColumn get id => text().clientDefault(newId)();
  TextColumn get cityId => text()();
  TextColumn get areaJson => text()();
  TextColumn get difficulty => textEnum<Difficulty>()();
  TextColumn get packVersion => text()();
  DateTimeColumn get startedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// The round whose Close and Miss streets this round retries.
  TextColumn get retryOf => text().nullable().references(Rounds, #id)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Answer')
class Answers extends Table {
  @override
  String get tableName => 'answer';

  TextColumn get id => text().clientDefault(newId)();
  TextColumn get roundId => text().references(Rounds, #id)();
  TextColumn get streetId => text()();
  RealColumn get pinLat => real()();
  RealColumn get pinLon => real()();
  RealColumn get distanceM => real()();
  TextColumn get tier => textEnum<Tier>()();
  TextColumn get packVersion => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The streets planned for a round, in order. With the answer log this
/// derives where a round stands, so rounds resume after an app kill.
@DataClassName('RoundQuestion')
class RoundQuestions extends Table {
  @override
  String get tableName => 'round_question';

  TextColumn get roundId => text().references(Rounds, #id)();
  IntColumn get position => integer()();
  TextColumn get streetId => text()();

  @override
  Set<Column<Object>> get primaryKey => {roundId, position};
}

/// Local dates when the daily XP goal was met; the streak, its freezes and
/// the best run are derived from them (pindoro_core `streakOf`).
@DataClassName('GoalDay')
class GoalDays extends Table {
  @override
  String get tableName => 'goal_day';

  /// The local date as `YYYY-MM-DD` (pindoro_core `dayKey`).
  TextColumn get date => text()();

  /// The round whose answer reached the goal; null when lowering it did.
  TextColumn get roundId => text().nullable().references(Rounds, #id)();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Streets the old game knew (a Great or Perfect in a lesson), kept from the
/// lesson tables when v3 dropped them, so carry-over still finds them.
@DataClassName('LegacyKnownRow')
class LegacyKnown extends Table {
  @override
  String get tableName => 'legacy_known';

  TextColumn get cityId => text()();
  TextColumn get streetId => text()();

  @override
  Set<Column<Object>> get primaryKey => {cityId, streetId};
}

/// The account (one row): its username, the secret token for its
/// `/me` routes (null once a sign-in on another phone signed this one out),
/// when this phone last backed up, and since when it has progress the backup
/// lacks. Left out of the backups.
@DataClassName('Account')
class Accounts extends Table {
  @override
  String get tableName => 'account';

  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get username => text()();
  TextColumn get token => text().nullable()();
  DateTimeColumn get backedUpAt => dateTime().nullable()();
  DateTimeColumn get changedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An earned badge (pindoro_learning `BadgeId` by name, or a City memory
/// milestone's `cityMemoryBadge`): saved once and never removed,
/// so a badge stays earned when its condition stops holding (a pack update
/// can unmaster a district).
@DataClassName('BadgeRow')
class Badges extends Table {
  @override
  String get tableName => 'badge';

  TextColumn get id => text()();
  DateTimeColumn get earnedAt => dateTime()();

  /// When the player saw it (its reward sheet closed, or Me showed it); null
  /// shows the New pill.
  DateTimeColumn get seenAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One learning card per item (docs/learning/SPEC.md §2.2); an unseen item
/// has no row. Mapped to pindoro_learning `CardState` by the learning
/// repository.
@DataClassName('CardStateRow')
class CardStates extends Table {
  @override
  String get tableName => 'card_state';

  TextColumn get itemId => text()();

  /// The item id's prefix (`P`, `N`, …), kept for filtering in SQL.
  TextColumn get type => text()();
  TextColumn get state => textEnum<CardPhase>()();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  DateTimeColumn get lastReviewAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();

  /// 1 Again … 4 Easy.
  IntColumn get lastRating => integer().nullable()();
  RealColumn get lastDistanceM => real().nullable()();
  TextColumn get lastSnapId => text().nullable()();
  BoolColumn get priorKnown => boolean().withDefault(const Constant(false))();
  DateTimeColumn get introAt => dateTime().nullable()();

  /// The player's memory aid for a leech (SPEC §4).
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

/// Every graded answer, append-only (`review_log_immutable.drift`): the
/// FSRS optimiser and the progress numbers replay it.
@DataClassName('ReviewLogRow')
class ReviewLogs extends Table {
  @override
  String get tableName => 'review_log';

  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get itemId => text()();
  TextColumn get type => text()();
  TextColumn get format => textEnum<ReviewFormat>()();

  /// 1 Again … 4 Easy.
  IntColumn get rating => integer()();
  RealColumn get distanceM => real().nullable()();
  TextColumn get snapId => text().nullable()();
  IntColumn get rtMs => integer().nullable()();
  RealColumn get elapsedDays => real().nullable()();
  RealColumn get rBefore => real().nullable()();
  RealColumn get sBefore => real().nullable()();
  RealColumn get dBefore => real().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get source => textEnum<ReviewSource>()();
}

/// A pin for [streetA] landed on [streetB] (a mix-up), [count] times.
@DataClassName('ConfusionRow')
class Confusions extends Table {
  @override
  String get tableName => 'confusion';

  TextColumn get streetA => text()();
  TextColumn get streetB => text()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {streetA, streetB};
}

/// Per city: when placement ended (or the player chose to start from zero)
/// and the home and work neighbourhoods new streets start in (SPEC §6.2, §6.3).
@DataClassName('LearnCityRow')
class LearnCities extends Table {
  @override
  String get tableName => 'learn_city';

  TextColumn get cityId => text()();
  DateTimeColumn get placedAt => dateTime().nullable()();
  TextColumn get homeId => text().nullable()();
  TextColumn get workId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {cityId};
}

/// The player's own landmarks (SPEC §2.2, §9): a name and kind at a junction,
/// seen from one approach (`n<OSM node id>` of the junction and of the
/// neighbouring junction along the approach) on the left or right.
@DataClassName('PersonalLandmarkRow')
class LandmarkPersonal extends Table {
  @override
  String get tableName => 'landmark_personal';

  /// `me:<uuidv7>`.
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// fuel, metro, worship, shop or other.
  TextColumn get kind => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  TextColumn get junctionId => text()();
  TextColumn get approachEdgeId => text()();

  /// left or right, driving in on the approach.
  TextColumn get side => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What each decision a recital or drive tested said about its J card (SPEC §2.2, §4): kept for
/// tuning; only a near-due failure also reviews the card.
@DataClassName('EvidenceRow')
class ImplicitEvidence extends Table {
  @override
  String get tableName => 'implicit_evidence';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemId => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get source => textEnum<ReviewSource>()();

  /// 1 the decision was right, 0 wrong.
  IntColumn get outcome => integer()();
}

/// The recitals' A → B (SPEC §16.7): route-book runs and weekly random pairs. Ends are
/// `n<OSM node id>`s of pack junctions; [items] the J items the best route drives,
/// space-separated.
@DataClassName('RunRow')
class Runs extends Table {
  @override
  String get tableName => 'run';

  /// `n<from node>:n<to node>`; its card is `R:<id>`.
  TextColumn get id => text()();
  IntColumn get fromNode => integer()();
  IntColumn get toNode => integer()();
  BoolColumn get random => boolean()();
  TextColumn get items => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What the player reported wrong in the pack on this phone: moves that are legal ("Wrong? Report
/// this turn", SPEC §15), a one-way driven the other way (`oneway:n<from>:n<to>`) or a restricted
/// turn (`turn:n<from>:n<via>:n<to>`) by OSM node ids, and places that are not there
/// (`place:<landmark id>`, "Can't find it?", SPEC §16.18 item 94).
@DataClassName('TurnOverrideRow')
class TurnOverrides extends Table {
  @override
  String get tableName => 'turn_override';

  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Every drive (SPEC §16.23 item 124), append-only (`drive_immutable.drift`); its track sits in
/// `drive_track` while it is kept.
@DataClassName('DriveRow')
class Drives extends Table {
  @override
  String get tableName => 'drive';

  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  TextColumn get level => textEnum<DriveLevel>()();

  /// The setup's choice: `run`, `surprise` or `own`.
  TextColumn get goal => text()();

  /// The destination's OSM node (pack junction ids change between packs); null when the pack
  /// has no node for it.
  IntColumn get targetNode => integer().nullable()();

  /// The destination street, by any of its parts' ids.
  TextColumn get targetStreet => text()();
  TextColumn get outcome => textEnum<DriveOutcome>()();
  RealColumn get drivenM => real()();

  /// Null when nothing was graded (no fix near a road, or the drive was abandoned).
  TextColumn get tier => textEnum<Tier>().nullable()();
  RealColumn get stretch => real().nullable()();
  IntColumn get uTurns => integer().nullable()();
  IntColumn get hesitations => integer().nullable()();

  /// Turns of the route book credited and failed.
  IntColumn get credited => integer()();
  IntColumn get failed => integer()();
  IntColumn get fixes => integer()();
  IntColumn get gpsGaps => integer()();
  IntColumn get longestGapS => integer()();

  /// The level suggested at setup (null before navigation), the recoveries and whether Off's
  /// Rescue was used (SPEC §16.23 items 114–116).
  TextColumn get suggested => textEnum<DriveLevel>().nullable()();
  IntColumn get recoveries => integer().withDefault(const Constant(0))();
  BoolColumn get rescued => boolean().withDefault(const Constant(false))();

  /// Where it started (the first junction's OSM node), the pack place driven to, and the level
  /// with the most help it reached (items 120–122); null on drives before schema 26.
  IntColumn get startNode => integer().nullable()();
  TextColumn get targetPlace => text().nullable()();
  TextColumn get mostHelp => textEnum<DriveLevel>().nullable()();

  /// The spot driven to, a place's or a pin's (item 132); null for a street or a junction, and
  /// on drives before schema 29.
  RealColumn get targetLat => real().nullable()();
  RealColumn get targetLon => real().nullable()();

  /// The first of its fixes the drive was graded from: where the destination last changed or
  /// the last stop on the way was reached (items 116, 134); null from the start, and on drives
  /// before schema 30.
  IntColumn get gradedFrom => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A drive's fixes (`encodeTrack`), dropped after `driveTrackKeepDays` (SPEC §16.23 item 124).
@DataClassName('DriveTrackRow')
class DriveTracks extends Table {
  @override
  String get tableName => 'drive_track';

  TextColumn get driveId => text().references(Drives, #id)();
  TextColumn get track => text()();

  @override
  Set<Column<Object>> get primaryKey => {driveId};
}

/// Each junction with a way on to choose on a drive (SPEC §16.23 item 124), append-only: the move
/// made ([itemKey], its J item id, null without OSM nodes), whether navigation had a decision
/// there ([planned]), whether it kept a good path ([ok], null in a GPS gap), the level and help.
@DataClassName('DriveDecisionRow')
class DriveDecisions extends Table {
  @override
  String get tableName => 'drive_decision';

  TextColumn get driveId => text().references(Drives, #id)();
  IntColumn get seq => integer()();
  DateTimeColumn get at => dateTime()();
  TextColumn get itemKey => text().nullable()();
  BoolColumn get planned => boolean()();
  BoolColumn get ok => boolean().nullable()();
  TextColumn get level => textEnum<DriveLevel>()();
  TextColumn get help => textEnum<NavHelp>()();

  /// A recovery within `noCreditAfterPromptS` before it.
  BoolColumn get recentHelp => boolean()();

  /// A hesitation within `hesitationBeforeM` of the junction.
  BoolColumn get hesitated => boolean()();

  /// One of the drive plan's key decisions (item 121): the preview's and the debrief's.
  BoolColumn get keyTurn => boolean().withDefault(const Constant(false))();

  /// What it did to its J card (item 124): the rating given (`good`, `hard`, `again`) or why
  /// none (a `CreditSkip`); null without a key or in a GPS gap.
  TextColumn get effect => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {driveId, seq};
}

/// What a drive's preview, recital of the turns, debrief and Point to home found, and what the
/// drive said, showed and was touched for (SPEC §16.23 item 124), append-only: per turn
/// ([itemKey]) or for the drive. A preview's rows carry the id the drive will have, so they may
/// name a drive never started.
@DataClassName('DriveEventRow')
class DriveEvents extends Table {
  @override
  String get tableName => 'drive_event';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get driveId => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get kind => textEnum<DriveEventKind>()();
  TextColumn get itemKey => text().nullable()();

  /// [DriveEventKind]'s number: seconds watched, 1 right and 0 wrong (null: not remembered),
  /// the turns gone through, the pointing error in degrees; a prompt's 1 said and 0 muted; the
  /// km/h at a touch.
  RealColumn get value => real().nullable()();

  /// [DriveEventKind]'s words: a prompt's kind, the screen shown (its level, then `recovery`,
  /// `lost` and `stopped` as they apply), a name's `heard` or `shown` (its street part id is
  /// [itemKey]); null before schema 28.
  TextColumn get detail => text().nullable()();
}

@DriftDatabase(
  tables: [
    UserSettings,
    Rounds,
    Answers,
    RoundQuestions,
    GoalDays,
    LegacyKnown,
    Badges,
    Accounts,
    CardStates,
    ReviewLogs,
    Confusions,
    LearnCities,
    LandmarkPersonal,
    ImplicitEvidence,
    Runs,
    TurnOverrides,
    Drives,
    DriveTracks,
    DriveDecisions,
    DriveEvents,
  ],
  include: {
    'answer_immutable.drift',
    'review_log_immutable.drift',
    'drive_immutable.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  /// The app opens it with `openDatabase()`, tests in memory.
  AppDatabase(super.e);

  static const int version = 30;

  @override
  int get schemaVersion => version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) => m.createTable(schema.roundQuestion),
      from2To3: (m, schema) => m.addColumn(schema.round, schema.round.retryOf),
      // Rebuilds the table: adds the preference columns, drops onboarding_done.
      from3To4: (m, schema) {
        final t = schema.userSettings;
        return m.alterTable(
          TableMigration(
            t,
            newColumns: [
              t.appLanguage,
              t.streetNames,
              t.theme,
              t.sound,
              t.haptics,
            ],
          ),
        );
      },
      from4To5: (m, schema) =>
          m.addColumn(schema.userSettings, schema.userSettings.homeCoachSeen),
      from5To6: (m, schema) async {
        await m.createTable(schema.goalDay);
        await m.addColumn(schema.userSettings, schema.userSettings.dailyGoal);
        await m.addColumn(schema.userSettings, schema.userSettings.reminder);
      },
      from6To7: (m, schema) async {
        await m.createTable(schema.reviewItem);
        await m.addColumn(schema.round, schema.round.pitStop);
      },
      from7To8: (m, schema) async {
        await m.createTable(schema.course);
        await m.createTable(schema.lessonResult);
        await m.createTable(schema.lessonAnswer);
      },
      from8To9: (m, schema) async {
        await m.createTable(schema.savedLesson);
        await m.addColumn(schema.userSettings, schema.userSettings.turnList);
      },
      from9To10: (m, schema) => m.createTable(schema.leaguePlayer),
      from10To11: (m, schema) async {
        await m.createTable(schema.badge);
        await m.createTable(schema.reviewCleared);
      },
      from11To12: (m, schema) => m.createTable(schema.account),
      // Rebuilds the table: the token becomes nullable, changed_at is new.
      from12To13: (m, schema) => m.alterTable(
        TableMigration(schema.account, newColumns: [schema.account.changedAt]),
      ),
      // Leagues sign in with the account, so the anonymous league player goes.
      from13To14: (m, schema) => m.deleteTable('league_player'),
      // The v3 learning system: cards, the append-only review log, mix-ups
      // and the minutes a day.
      from14To15: (m, schema) async {
        await m.createTable(schema.cardState);
        await m.createTable(schema.reviewLog);
        await m.createTable(schema.confusion);
        await m.create(schema.reviewLogNoUpdate);
        await m.create(schema.reviewLogNoDelete);
        await m.addColumn(
          schema.userSettings,
          schema.userSettings.minutesPerDay,
        );
      },
      from15To16: (m, schema) => m.createTable(schema.learnCity),
      // v3 replaces the old game layer: lessons, the Path, the Pit stop, XP
      // and the daily XP goal go. Lesson knowledge stays for carry-over.
      from16To17: (m, schema) async {
        await m.createTable(schema.legacyKnown);
        await customStatement('''
          INSERT OR IGNORE INTO legacy_known (city_id, street_id)
          SELECT r.city_id, a.street_id
          FROM lesson_answer a JOIN lesson_result r ON r.id = a.result_id
          WHERE a.kind <> 'trip' AND a.tier IN ('perfect', 'great')
            AND NOT (a.kind = 'name' AND a.fix = 1)
        ''');
        for (final table in [
          'saved_lesson',
          'lesson_answer',
          'lesson_result',
          'course',
          'review_item',
          'review_cleared',
        ]) {
          await m.deleteTable(table);
        }
        await m.dropColumn(schema.answer, 'xp');
        await m.dropColumn(schema.round, 'pit_stop');
        await m.dropColumn(schema.userSettings, 'daily_goal');
        await m.dropColumn(schema.userSettings, 'turn_list');
      },
      from17To18: (m, schema) =>
          m.addColumn(schema.cardState, schema.cardState.note),
      from18To19: (m, schema) => m.createTable(schema.landmarkPersonal),
      from19To20: (m, schema) async {
        await m.createTable(schema.implicitEvidence);
        await m.createTable(schema.run);
        await m.createTable(schema.turnOverride);
      },
      from20To21: (m, schema) =>
          m.addColumn(schema.userSettings, schema.userSettings.fsrsWeights),
      from21To22: (m, schema) =>
          m.addColumn(schema.userSettings, schema.userSettings.zoomButtons),
      from22To23: (m, schema) async {
        await m.createTable(schema.drive);
        await m.createTable(schema.driveTrack);
        await m.create(schema.driveNoUpdate);
        await m.create(schema.driveNoDelete);
      },
      from23To24: (m, schema) async {
        await m.createTable(schema.driveDecision);
        await m.create(schema.driveDecisionNoUpdate);
        await m.create(schema.driveDecisionNoDelete);
      },
      from24To25: (m, schema) async {
        await m.addColumn(
          schema.userSettings,
          schema.userSettings.speedToleranceKmh,
        );
        await m.addColumn(schema.drive, schema.drive.suggested);
        await m.addColumn(schema.drive, schema.drive.recoveries);
        await m.addColumn(schema.drive, schema.drive.rescued);
      },
      from25To26: (m, schema) async {
        await m.addColumn(schema.userSettings, schema.userSettings.driveHome);
        await m.addColumn(schema.userSettings, schema.userSettings.driveWork);
        await m.addColumn(schema.userSettings, schema.userSettings.drivePlan);
        await m.addColumn(schema.drive, schema.drive.startNode);
        await m.addColumn(schema.drive, schema.drive.targetPlace);
        await m.addColumn(schema.drive, schema.drive.mostHelp);
        await m.addColumn(schema.driveDecision, schema.driveDecision.keyTurn);
        await m.addColumn(schema.driveDecision, schema.driveDecision.effect);
        await m.createTable(schema.driveEvent);
        await m.create(schema.driveEventNoUpdate);
        await m.create(schema.driveEventNoDelete);
      },
      from26To27: (m, schema) =>
          m.addColumn(schema.userSettings, schema.userSettings.driveMarker),
      from27To28: (m, schema) =>
          m.addColumn(schema.driveEvent, schema.driveEvent.detail),
      from28To29: (m, schema) async {
        await m.addColumn(schema.drive, schema.drive.targetLat);
        await m.addColumn(schema.drive, schema.drive.targetLon);
      },
      from29To30: (m, schema) =>
          m.addColumn(schema.drive, schema.drive.gradedFrom),
    ),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Overridden in main() and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
