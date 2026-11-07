import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/launch_overlay.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;
  late _FakeReminders reminders;
  late List<Street> streets;

  setUpAll(() {
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    streets = pack.streets(districtId: AppConfig.fixtureDistrictId);
    pack.close();
  });

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    reminders = _FakeReminders();
  });
  tearDown(() => db.close());

  Widget appAt(String location, {bool coldStart = false}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      remindersProvider.overrideWithValue(reminders),
      packRepositoryProvider.overrideWith((ref) async {
        final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
        ref.onDispose(repo.close);
        return repo;
      }),
    ],
    child: PindoroApp(initialLocation: location, coldStart: coldStart),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  /// On a phone-sized screen (the emulator's 1080 × 2400).
  Future<void> pumpApp(WidgetTester tester, String location) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appAt(location));
    await settle(tester);
  }

  const vake = DistrictsArea({AppConfig.fixtureDistrictId});

  /// A round in Vake with [answered] answers; also picks Vake unless
  /// [pickArea] is false (a settings write while the app runs would wait on
  /// its settings query, which only advances when the test pumps).
  Future<String> roundWithAnswers(
    int answered, {
    Tier tier = Tier.great,
    int xp = 60,
    bool pickArea = true,
  }) async {
    if (pickArea) await SettingsDao(db).chooseArea(vake, cityId: 'tbilisi');
    final id = await ProgressDao(db).startRound(
      cityId: 'tbilisi',
      area: vake,
      difficulty: Difficulty.expert,
      packVersion: 'v1',
      streetIds: [for (final s in streets.take(10)) s.id],
    );
    for (final s in streets.take(answered)) {
      await db
          .into(db.answers)
          .insert(
            AnswersCompanion.insert(
              roundId: id,
              streetId: s.id,
              pinLat: s.midpoint.lat,
              pinLon: s.midpoint.lon,
              distanceM: 42,
              tier: tier,
              xp: xp,
              packVersion: 'v1',
            ),
          );
    }
    return id;
  }

  testWidgets('home without an area asks for one', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Choose an area'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Streets you know'), findsOneWidget);
  });

  testWidgets('home asks for an area the open pack lacks (offline Vake)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dao = SettingsDao(db);
      await dao.chooseArea(const DistrictsArea({'osm:r1'}), cityId: 'tbilisi');
      await dao.chooseDifficulty(Difficulty.easy);
    });
    await pumpApp(tester, Routes.home);
    expect(find.text('Choose an area'), findsOneWidget);
  });

  testWidgets('a cold start plays the launch, then leaves home usable', (
    tester,
  ) async {
    final launchPin = find.descendant(
      of: find.byType(LaunchOverlay),
      matching: find.byType(PinMark),
    );
    await tester.pumpWidget(appAt(Routes.home, coldStart: true));
    expect(launchPin, findsOneWidget);

    await settle(tester);
    expect(launchPin, findsNothing);
    expect(find.text('Streets you know'), findsOneWidget);
  });

  testWidgets('the first home shows one coach mark; a tap closes it for good', (
    tester,
  ) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Your city fills in here'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your city fills in here'), findsNothing);
    final settings = (await tester.runAsync(SettingsDao(db).read))!;
    expect(settings.homeCoachSeen, isTrue);
  });

  testWidgets('home offers to continue an unfinished round', (tester) async {
    await tester.runAsync(() => roundWithAnswers(1));
    await pumpApp(tester, Routes.home);
    expect(find.text('Round in progress'), findsOneWidget);
    expect(find.text('Continue round'), findsOneWidget);
    expect(find.text('Start a new round instead'), findsOneWidget);
  });

  testWidgets('home picks up a round played while it waited underneath', (
    tester,
  ) async {
    await tester.runAsync(
      () => SettingsDao(db).chooseArea(vake, cityId: 'tbilisi'),
    );
    await pumpApp(tester, Routes.home);
    expect(find.text('Round in progress'), findsNothing);
    // The quiz writes while Home stays in the navigator, then goes back to it.
    await tester.runAsync(() => roundWithAnswers(1, pickArea: false));
    await settle(tester);
    expect(find.text('Round in progress'), findsOneWidget);
  });

  testWidgets('results list each answer with its street and the level', (
    tester,
  ) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2, xp: 600)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    expect(find.text('Level 2!'), findsOneWidget, reason: 'level-up moment');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultRow), findsNWidgets(2));
    expect(find.text(streets[0].nameKa), findsOneWidget);
    expect(find.text('+600'), findsNWidgets(2));
    expect(find.text('+1 200 XP'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
  });

  testWidgets('done on results counts the round into home', (tester) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Streets you know'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget, reason: 'newly known streets');
    expect(find.text('+120 XP'), findsOneWidget, reason: 'tip on the bar');
    expect(find.text('120'), findsOneWidget, reason: 'XP pill counted up');
  });

  testWidgets('results offer to retry Close and Miss streets', (tester) async {
    final missed = (await tester.runAsync(
      () => roundWithAnswers(3, tier: Tier.miss),
    ))!;
    await pumpApp(tester, '${Routes.results}?round=$missed');
    expect(find.text('Retry 3 missed'), findsOneWidget);
    expect(find.text('Change settings'), findsOneWidget);
  });

  testWidgets('a tough round makes retry the main action', (tester) async {
    final tough = (await tester.runAsync(
      () => roundWithAnswers(5, tier: Tier.miss),
    ))!;
    await pumpApp(tester, '${Routes.results}?round=$tough');
    expect(find.text('Retry 5 missed'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Change settings'), findsNothing);
  });

  testWidgets('results without Close or Miss offer no retry', (tester) async {
    final great = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$great');
    expect(find.textContaining('Retry'), findsNothing);
  });

  testWidgets('results without a round go home', (tester) async {
    await pumpApp(tester, Routes.results);
    expect(find.text('Streets you know'), findsOneWidget);
  });

  group('streak', () {
    final today = calendarDay(DateTime.now());

    /// Goal days from [from] days ago to [to] days ago.
    Future<void> goalDays(int from, int to) => db.batch(
      (b) => b.insertAll(db.goalDays, [
        for (var d = from; d >= to; d--)
          GoalDaysCompanion.insert(
            date: dayKey(today.subtract(Duration(days: d))),
          ),
      ]),
    );

    testWidgets('home shows the pill and ring; the pill opens Streak', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await roundWithAnswers(10);
        await goalDays(1, 0);
        await SettingsDao(db).markHomeCoachSeen();
      });
      await pumpApp(tester, Routes.home);
      expect(
        find.bySemanticsLabel('2-day streak. Goal met today.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Daily goal met, 600 of 500 XP'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel('2-day streak. Goal met today.'));
      await settle(tester);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('Your best: 2 days'), findsOneWidget);
      expect(find.text('No streak freeze yet'), findsOneWidget);
      expect(find.text('Met today with 600 XP'), findsOneWidget);
    });

    testWidgets('streak shows a held freeze; Change saves a new goal', (
      tester,
    ) async {
      await tester.runAsync(() => goalDays(7, 1));
      await pumpApp(tester, Routes.streak);
      expect(find.text('Streak freeze equipped · 1 of 2'), findsOneWidget);
      expect(find.text('0 of 500 XP today'), findsOneWidget);

      await tester.ensureVisible(find.text('Change'));
      await tester.pump();
      await tester.tap(find.text('Change'));
      await settle(tester);
      await tester.tap(find.text('${formatNumber(1000)} XP a day'));
      await settle(tester);
      expect(find.text('Daily goal: ${formatNumber(1000)} XP'), findsOneWidget);
      final settings = await tester.runAsync(() => SettingsDao(db).read());
      expect(settings!.dailyGoal, 1000);
    });

    testWidgets('results show the streak once the round met today\'s goal', (
      tester,
    ) async {
      late String id;
      await tester.runAsync(() async {
        id = await roundWithAnswers(10);
        await goalDays(1, 1);
        await db
            .into(db.goalDays)
            .insert(
              GoalDaysCompanion.insert(date: dayKey(today), roundId: Value(id)),
            );
      });
      await pumpApp(tester, Routes.resultsOf(id));
      expect(find.text('2-day streak'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Daily goal met, 2-day streak'),
        findsOneWidget,
      );
    });

    testWidgets('settings show and change the daily goal', (tester) async {
      await pumpApp(tester, Routes.settings);
      expect(find.text('500 XP a day'), findsOneWidget);
      expect(
        find.text('About two rounds · keeps your streak going'),
        findsOneWidget,
      );
      await tester.tap(find.text('500 XP a day'));
      await settle(tester);
      await tester.tap(find.text('250 XP a day'));
      await settle(tester);
      expect(
        find.text('About one round · keeps your streak going'),
        findsOneWidget,
      );
    });

    testWidgets('a goal lowered below today\'s XP marks today', (tester) async {
      await tester.runAsync(() => roundWithAnswers(5)); // 300 XP
      await pumpApp(tester, Routes.streak);
      expect(find.text('300 of 500 XP today'), findsOneWidget);
      await tester.ensureVisible(find.text('Change'));
      await tester.pump();
      await tester.tap(find.text('Change'));
      await settle(tester);
      await tester.tap(find.text('250 XP a day'));
      await settle(tester);
      expect(find.text('Met today with 300 XP'), findsOneWidget);
      final days = await tester.runAsync(ProgressDao(db).goalDayRounds);
      expect(days, {today: null});
    });

    testWidgets('XP from before the streak existed counts for today', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await roundWithAnswers(10); // 600 XP, no goal day written
        await SettingsDao(db).markHomeCoachSeen();
      });
      await pumpApp(tester, Routes.home);
      expect(
        find.bySemanticsLabel('1-day streak. Goal met today.'),
        findsOneWidget,
      );
    });

    testWidgets('the reminder asks first, then schedules the next one', (
      tester,
    ) async {
      await pumpApp(tester, Routes.settings);
      await tester.tap(find.text('Reminder'));
      await settle(tester);
      final settings = await tester.runAsync(() => SettingsDao(db).read());
      expect(settings!.reminder, isTrue);
      expect(reminders.scheduled.single.hour, StreakRules.reminderHour);

      await tester.tap(find.text('Reminder'));
      await settle(tester);
      expect(reminders.cancels, 1);
    });

    testWidgets('without permission the reminder stays off', (tester) async {
      reminders.allowed = false;
      await pumpApp(tester, Routes.settings);
      await tester.tap(find.text('Reminder'));
      await settle(tester);
      expect(
        find.text(
          "Notifications are off for Pindoro. Turn them on in your phone's "
          'settings.',
        ),
        findsOneWidget,
      );
      final settings = await tester.runAsync(() => SettingsDao(db).read());
      expect(settings!.reminder, isFalse);
      expect(reminders.scheduled, isEmpty);
    });
  });

  group('me', () {
    testWidgets('level, stats and cities; a city opens Free play', (
      tester,
    ) async {
      // One Great of 4 000 XP: level 4 (from 3 750), today's goal met.
      await tester.runAsync(() => roundWithAnswers(1, xp: 4000));
      await pumpApp(tester, Routes.me);
      expect(find.text('Level 4'), findsOneWidget);
      expect(find.textContaining('playing since'), findsOneWidget);
      expect(find.text('${formatNumber(1500)} XP to level 5'), findsOneWidget);
      for (final label in [
        'Streets known, 1',
        'Lessons, 0',
        'Road trips, 0',
        'Best streak, 1 day',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      final tbilisi = find.bySemanticsLabel(
        RegExp(r'^Tbilisi, 1 of \S+ streets known$'),
      );
      expect(tbilisi, findsOneWidget);

      await tester.tap(tbilisi);
      await settle(tester);
      expect(find.text('Streets you know'), findsOneWidget);
    });
  });

  group('pit stop', () {
    final today = calendarDay(DateTime.now());

    /// The fixture's first streets in the Pit stop, due [dueIn] days from
    /// today (negative: overdue).
    Future<void> review(int count, {int dueIn = -1}) => db.batch(
      (b) => b.insertAll(db.reviewItems, [
        for (final s in streets.take(count))
          ReviewItemsCompanion.insert(
            cityId: 'tbilisi',
            streetId: s.id,
            step: 1,
            greatRun: 0,
            dueOn: dayKey(today.add(Duration(days: dueIn))),
            lastTier: Tier.miss,
            lastAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
      ]),
    );

    testWidgets('the Pit stop tab counts and lists the due streets', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await review(6);
        await SettingsDao(db).markHomeCoachSeen();
      });
      await pumpApp(tester, Routes.home);
      final tab = find.bySemanticsLabel('Pit stop, 6 streets due');
      expect(tab, findsOneWidget);

      await tester.tap(tab);
      await settle(tester);
      expect(find.text('6 streets to tune up'), findsOneWidget);
      expect(find.text('+ 2 more streets'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Miss, 1 day ago\. Review step 1 of 4')),
        findsNWidgets(4),
      );
      expect(find.text('Start Pit stop · 6 streets'), findsOneWidget);
    });

    testWidgets('nothing due: all tuned up, with the next review', (
      tester,
    ) async {
      await tester.runAsync(() => review(3, dueIn: 1));
      await pumpApp(tester, Routes.pitStop);
      expect(find.text('All tuned up'), findsOneWidget);
      expect(find.text('Next review: tomorrow · 3 streets'), findsOneWidget);
    });

    testWidgets('a Pit stop round ends in Pit stop results', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await ProgressDao(db).startRound(
          cityId: 'tbilisi',
          area: vake,
          difficulty: Difficulty.expert,
          packVersion: 'v1',
          streetIds: [streets[0].id, streets[1].id],
          pitStop: true,
        );
        for (final (s, tier) in [
          (streets[0], Tier.great),
          (streets[1], Tier.miss),
        ]) {
          await ProgressDao(db).recordAnswer(
            roundId: id,
            streetId: s.id,
            pin: s.midpoint,
            distanceM: 42,
            tier: tier,
            xp: tier == Tier.great ? 80 : 0,
            packVersion: 'v1',
          );
        }
        await ProgressDao(db).finishRound(id);
      });
      await pumpApp(tester, Routes.resultsOf(id));
      expect(find.text('Pit stop complete'), findsOneWidget);
      expect(find.text('1 to your Pit stop'), findsOneWidget);
      expect(find.text('Play a new round'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('in your Pit stop', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

/// Records what would be scheduled; [allowed] answers the permission prompt.
class _FakeReminders implements Reminders {
  bool allowed = true;
  final List<DateTime> scheduled = [];
  int cancels = 0;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> schedule(ReminderNotice notice) async =>
      scheduled.add(notice.at);

  @override
  Future<void> cancel() async => cancels++;
}
