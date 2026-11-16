import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

void main() {
  const vake = DistrictsArea({AppConfig.fixtureDistrictId});
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container({PackRepository Function()? pack}) {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        packRepositoryProvider.overrideWith((ref) async {
          final repo =
              pack?.call() ??
              SqlitePackRepository.open(AppConfig.fixturePackAsset);
          ref.onDispose(repo.close);
          return repo;
        }),
        questionSelectorProvider.overrideWithValue(
          QuestionSelector(random: Random(7)),
        ),
      ],
    );
    c.listen(roundControllerProvider, (_, _) {}); // keep it alive
    addTearDown(c.dispose);
    return c;
  }

  /// Answers on the street, or far away (a Miss) when [miss].
  Future<void> answerCurrent(
    RoundController controller,
    ProviderContainer c, {
    bool miss = false,
  }) async {
    final street =
        (c.read(roundControllerProvider) as RoundAsking).round.current;
    controller.placePin(
      miss ? const LatLng(41.9, 45.2) : street.geometry.first.first,
    );
    await controller.confirm();
  }

  test('start plans 10 streets and asks the first', () async {
    final c = container();
    await c
        .read(roundControllerProvider.notifier)
        .start(vake, Difficulty.expert);
    final state = c.read(roundControllerProvider) as RoundAsking;
    expect(state.round.questions, hasLength(QuestionSelector.roundSize));
    expect(state.round.number, 1);
    expect(state.pin, isNull);
    final progress = await ProgressDao(db).roundProgress(state.round.id);
    expect(progress.planned, [for (final s in state.round.questions) s.id]);
  });

  test('confirm needs a pin, then logs the scored answer', () async {
    final c = container();
    final controller = c.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    await controller.confirm();
    expect(c.read(roundControllerProvider), isA<RoundAsking>());

    await answerCurrent(controller, c);
    final revealed = c.read(roundControllerProvider) as RoundRevealed;
    expect(revealed.answer.distanceM, closeTo(0, 0.5));
    expect(revealed.answer.tier, Tier.perfect);
    expect(
      await ProgressDao(db).answersForRound(revealed.round.id),
      hasLength(1),
    );
  });

  test('an Explore pin feeds the learning cards (SPEC §16.16): a first-sight '
      'Good makes a known card, a miss is only logged', () async {
    final c = container();
    final controller = c.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    final first =
        (c.read(roundControllerProvider) as RoundAsking).round.current;
    await answerCurrent(controller, c);
    await controller.next();
    await answerCurrent(controller, c, miss: true);
    final learning = LearningDao(db);
    final cards = await learning.cards();
    expect(cards.map((card) => card.itemId), [CardType.p.item(first.id)]);
    expect(cards.single.priorKnown, isTrue);
    expect((await learning.log()).map((e) => e.format), [
      ReviewFormat.explore,
      ReviewFormat.exploreLog,
    ]);
  });

  test('a new controller resumes at the next unanswered street', () async {
    final first = container();
    final controller = first.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    await answerCurrent(controller, first);
    final round = (first.read(roundControllerProvider) as RoundRevealed).round;

    final second = container();
    await second.read(roundControllerProvider.notifier).resume(round.id);
    final resumed = second.read(roundControllerProvider) as RoundAsking;
    expect(resumed.round.number, 2);
    expect(resumed.round.current.id, round.questions[1].id);
  });

  test('the tenth answer finishes the round, before Next', () async {
    final c = container();
    final controller = c.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    final id = (c.read(roundControllerProvider) as RoundAsking).round.id;
    for (var i = 0; i < QuestionSelector.roundSize; i++) {
      await answerCurrent(controller, c);
      if (i < QuestionSelector.roundSize - 1) await controller.next();
    }
    expect(c.read(roundControllerProvider), isA<RoundRevealed>());
    expect(
      (await ProgressDao(db).roundProgress(id)).round.finishedAt,
      isNotNull,
      reason: 'leaving on the last reveal must not leave it to resume',
    );
    expect(await ProgressDao(db).resumableRound(DateTime.now()), isNull);
    await controller.next();
    expect(c.read(roundControllerProvider), isA<RoundFinished>());
  });

  test('a retry round asks the Close and Miss streets of a round', () async {
    final c = container();
    final controller = c.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    final first = (c.read(roundControllerProvider) as RoundAsking).round;
    for (var i = 0; i < first.total; i++) {
      await answerCurrent(controller, c, miss: i == 1 || i == 4);
      await controller.next();
    }

    await controller.startRetry(first.id);
    final retry = (c.read(roundControllerProvider) as RoundAsking).round;
    expect(retry.total, 2);
    expect(
      [for (final q in retry.questions) q.id],
      [first.questions[1].id, first.questions[4].id],
    );
    expect(
      (await ProgressDao(db).roundProgress(retry.id)).round.retryOf,
      first.id,
    );

    for (var i = 0; i < retry.total; i++) {
      await answerCurrent(controller, c);
      await controller.next();
    }
    expect(c.read(roundControllerProvider), isA<RoundFinished>());
    expect((await ProgressDao(db).roundProgress(retry.id)).retryIds, isEmpty);
  });

  test('a resumed round leaves retired streets off the question bar', () async {
    final first = container();
    final controller = first.read(roundControllerProvider.notifier);
    await controller.start(vake, Difficulty.expert);
    await answerCurrent(controller, first);
    await controller.next();
    await answerCurrent(controller, first);
    final round = (first.read(roundControllerProvider) as RoundRevealed).round;
    final retired = {for (final p in round.questions[1].street.parts) p.id};

    final second = container(
      pack: () => _FilteredPack(
        SqlitePackRepository.open(AppConfig.fixturePackAsset),
        (streets) => [
          for (final s in streets)
            if (!retired.contains(s.id)) s,
        ],
      ),
    );
    await second.read(roundControllerProvider.notifier).resume(round.id);
    final resumed = (second.read(roundControllerProvider) as RoundAsking).round;
    expect(resumed.total, QuestionSelector.roundSize - 1);
    expect(resumed.number, 2);
    expect(resumed.answeredTiers, hasLength(1));
  });

  test('a pool smaller than a round is reported', () async {
    final c = container(
      pack: () => _FilteredPack(
        SqlitePackRepository.open(AppConfig.fixturePackAsset),
        (streets) => streets.take(3).toList(),
      ),
    );
    await c
        .read(roundControllerProvider.notifier)
        .start(vake, Difficulty.expert);
    expect(
      c.read(roundControllerProvider),
      isA<RoundNotEnough>().having((s) => s.count, 'count', lessThan(4)),
    );
  });

  test('an area missing from the pack is reported', () async {
    final c = container();
    await c
        .read(roundControllerProvider.notifier)
        .start(const DistrictsArea({'osm:r1'}), Difficulty.expert);
    expect(c.read(roundControllerProvider), isA<RoundAreaMissing>());
  });
}

/// The fixture with every street query passed through [_keep].
class _FilteredPack implements PackRepository {
  _FilteredPack(this._inner, this._keep);

  final PackRepository _inner;
  final List<Street> Function(List<Street>) _keep;

  @override
  List<Street> streets({String? districtId, Set<Difficulty>? difficulties}) =>
      _keep(_inner.streets(districtId: districtId, difficulties: difficulties));

  @override
  Map<String, String> meta() => _inner.meta();

  @override
  City city() => _inner.city();

  @override
  List<District> districts() => _inner.districts();

  @override
  Map<String, Set<String>> partsByDistrict() => _inner.partsByDistrict();

  @override
  Map<String, Map<String, double>> lengthsByDistrict() =>
      _inner.lengthsByDistrict();

  @override
  RoadGraph? roadGraph() => _inner.roadGraph();

  @override
  List<FamilyLink> families() => _inner.families();

  @override
  Map<String, Set<String>> chunkNeighbours() => _inner.chunkNeighbours();

  @override
  Map<int, int> junctionNodes() => _inner.junctionNodes();

  @override
  List<Bridge> bridges() => _inner.bridges();

  @override
  List<Landmark> landmarks() => _inner.landmarks();

  @override
  List<JunctionItem> junctionItems() => _inner.junctionItems();

  @override
  void close() => _inner.close();
}
