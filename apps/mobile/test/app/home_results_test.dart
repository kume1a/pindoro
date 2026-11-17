import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/launch_overlay.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/map/ui/explore_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

import '../support/settle.dart' show scrollTo;

void main() {
  late AppDatabase db;
  late _FakeReminders reminders;
  late List<Street> streets;

  /// What the server answers; offline unless a test says otherwise.
  late http.Response Function(http.Request) serverReply;

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
    serverReply = (_) => http.Response('', 503);
  });
  tearDown(() => db.close());

  Widget appAt(String location, {bool coldStart = false}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      remindersProvider.overrideWithValue(reminders),
      apiClientProvider.overrideWithValue(
        ApiClient(
          'https://api.example',
          client: MockClient((request) async => serverReply(request)),
        ),
      ),
      packRepositoryProvider.overrideWith((ref) async {
        final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
        ref.onDispose(repo.close);
        return repo;
      }),
      exploreMapBuilderProvider.overrideWithValue(
        (_) => const SizedBox.expand(),
      ),
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
              packVersion: 'v1',
            ),
          );
    }
    return id;
  }

  /// Finishes round [id]; Explore's coach mark has been seen by then, so it
  /// doesn't cover the sheet.
  Future<void> finished(String id) async {
    await ProgressDao(db).finishRound(id);
    await SettingsDao(db).markHomeCoachSeen();
  }

  testWidgets('home without an area asks for one', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Choose an area'), findsOneWidget);
    expect(find.text('Tbilisi in memory'), findsOneWidget);
  });

  testWidgets('on the Vake stand-in, Home offers the whole city', (
    tester,
  ) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Only Vake is on your phone'), findsNothing);
    ProviderScope.containerOf(
      tester.element(find.byType(PindoroApp)),
    ).read(offlineVakeProvider.notifier).set(true);
    await settle(tester);
    expect(find.text('Only Vake is on your phone'), findsOneWidget);
    expect(find.text('Download Tbilisi'), findsOneWidget);
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
    expect(find.text('Tbilisi in memory'), findsOneWidget);
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

  testWidgets('results list each answer with its street, no points', (
    tester,
  ) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    expect(find.byType(ResultRow), findsNWidgets(2));
    expect(find.text(streets[0].nameKa), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
  });

  testWidgets('done on results counts the round into home', (tester) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await tester.runAsync(() => finished(id));
    await pumpApp(tester, '${Routes.results}?round=$id');
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tbilisi in memory'), findsOneWidget);
    await scrollTo(tester, find.text('Last round'));
    expect(
      find.bySemanticsLabel('0 Perfect, 2 Great, 0 Close, 0 Miss'),
      findsOneWidget,
      reason: 'the round just played',
    );
  });

  testWidgets('back on results goes home, as Done does', (tester) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await tester.runAsync(() => finished(id));
    await pumpApp(tester, '${Routes.results}?round=$id');
    await tester.binding.handlePopRoute();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tbilisi in memory'), findsOneWidget);
    await scrollTo(tester, find.text('Last round'));
    expect(
      find.bySemanticsLabel('0 Perfect, 2 Great, 0 Close, 0 Miss'),
      findsOneWidget,
      reason: 'the round counted in',
    );
  });

  testWidgets('Explore offers quick starts: retry the last round’s misses, '
      'its area again, a random district', (tester) async {
    final missed = (await tester.runAsync(
      () => roundWithAnswers(10, tier: Tier.miss),
    ))!;
    await tester.runAsync(() => finished(missed));
    await pumpApp(tester, Routes.home);
    expect(find.text('Quick starts'), findsOneWidget);
    expect(find.text('Retry 10 missed'), findsOneWidget);
    expect(find.textContaining('again'), findsOneWidget);
    expect(find.text('A random district'), findsOneWidget);
    await scrollTo(tester, find.text('Areas you played'));
  });

  testWidgets('before any play, Explore explains itself and offers to start '
      'near home', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.textContaining('Play a round anywhere'), findsOneWidget);
    expect(find.text('Near home'), findsOneWidget);
    expect(find.text('Last round'), findsNothing);
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
    expect(find.text('Tbilisi in memory'), findsOneWidget);
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

    testWidgets('Today shows the pill; it opens Streak', (tester) async {
      await tester.runAsync(() async {
        await goalDays(1, 0);
        await LearningDao(db).markPlaced('tbilisi', DateTime(2026));
      });
      await pumpApp(tester, Routes.today);
      final pill = find.bySemanticsLabel('2-day streak. Goal met today.');
      expect(pill, findsOneWidget);

      await tester.tap(pill);
      await settle(tester);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('Your best: 2 days'), findsOneWidget);
      expect(find.text('No streak freeze yet'), findsOneWidget);
      expect(find.textContaining('A day counts'), findsOneWidget);
    });

    testWidgets('streak shows a held freeze', (tester) async {
      await tester.runAsync(() => goalDays(7, 1));
      await pumpApp(tester, Routes.streak);
      expect(find.text('Streak freeze equipped · 1 of 2'), findsOneWidget);
    });

    testWidgets('results show the streak once the round made today count', (
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

    testWidgets('the reminder asks first, then schedules the next one while '
        'reviews are due', (tester) async {
      await tester.runAsync(
        () => LearningDao(db).putCard(
          CardState(
            itemId: 'P:x',
            phase: CardPhase.review,
            memory: Memory(
              stability: 3,
              difficulty: 5,
              lastReview: DateTime.now().subtract(const Duration(days: 5)),
            ),
            dueAt: DateTime.now().subtract(const Duration(days: 1)),
            lastRating: Rating.good,
          ),
        ),
      );
      await pumpApp(tester, Routes.learnSettings);
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
      await pumpApp(tester, Routes.learnSettings);
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
    testWidgets('stats, badges and cities; a city opens Today', (tester) async {
      await tester.runAsync(() async {
        await roundWithAnswers(1);
        await LearningDao(db).markPlaced('tbilisi', DateTime(2026));
      });
      await pumpApp(tester, Routes.me);
      expect(find.textContaining('Playing since'), findsOneWidget);
      for (final label in [
        'Streets in memory, 0',
        'Pins dropped, 1',
        'Days counted, 0',
        'Best streak, 0 days',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      final tbilisi = find.bySemanticsLabel(
        RegExp(r'^Tbilisi, 0 of \S+ streets in memory$'),
      );
      expect(tbilisi, findsOneWidget);

      await tester.tap(tbilisi);
      await settle(tester);
      expect(find.byType(CityMemoryRow), findsOneWidget);
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
