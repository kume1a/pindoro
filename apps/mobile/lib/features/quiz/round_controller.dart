import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../app/database.dart';
import '../pack/sqlite_pack_repository.dart';

/// Overridden in tests with a seeded Random.
final questionSelectorProvider = Provider<QuestionSelector>(
  (ref) => QuestionSelector(),
);

final roundControllerProvider =
    NotifierProvider.autoDispose<RoundController, RoundState>(
      RoundController.new,
    );

/// What a round needs while it is played.
class RoundContext {
  const RoundContext({
    required this.id,
    required this.shape,
    required this.difficulty,
    required this.packVersion,
    required this.questions,
    required this.index,
  });

  final String id;
  final AreaShape shape;
  final Difficulty difficulty;
  final String packVersion;

  /// Planned streets present in the active pack, in round order.
  final List<Street> questions;
  final int index;

  Street get current => questions[index];
  int get number => index + 1;
  int get total => questions.length;
  bool get isLast => index == questions.length - 1;

  RoundContext advance() => RoundContext(
    id: id,
    shape: shape,
    difficulty: difficulty,
    packVersion: packVersion,
    questions: questions,
    index: index + 1,
  );
}

sealed class RoundState {
  const RoundState();
}

final class RoundLoading extends RoundState {
  const RoundLoading();
}

final class RoundNotEnough extends RoundState {
  const RoundNotEnough(this.count);

  final int count;
}

final class RoundAreaMissing extends RoundState {
  const RoundAreaMissing();
}

final class RoundFinished extends RoundState {
  const RoundFinished(this.roundId);

  final String roundId;
}

sealed class RoundInPlay extends RoundState {
  const RoundInPlay(this.round, this.pin);

  final RoundContext round;
  final LatLng? pin;
}

final class RoundAsking extends RoundInPlay {
  const RoundAsking(super.round, [super.pin]);
}

final class RoundRevealed extends RoundInPlay {
  const RoundRevealed(
    super.round,
    LatLng super.pin, {
    required this.answer,
    required this.nearest,
  });

  final Answer answer;

  /// Closest point of the street to the pin (end of the measure line).
  final LatLng nearest;
}

class RoundController extends Notifier<RoundState> {
  bool _saving = false;

  @override
  RoundState build() => const RoundLoading();

  AppDatabase get _db => ref.read(databaseProvider);

  Future<void> start(Area area, Difficulty difficulty) async {
    state = const RoundLoading();
    final pack = await ref.read(packRepositoryProvider.future);
    final shape = area.shapeIn(pack);
    if (shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    final streets = pack.streets(
      districtId: area.districtId,
      difficulties: difficulty.pool,
    );
    final lastTiers = await _db.lastTierByStreet();
    final recent = await _db.recentlyAnsweredStreetIds();
    final selection = ref.read(questionSelectorProvider).select([
      for (final s in streets)
        QuestionCandidate(
          streetId: s.id,
          midpoint: s.midpoint,
          knowledge: knowledgeFrom(lastTiers[s.id]),
        ),
    ], recentlyAsked: recent);
    switch (selection) {
      case NotEnoughStreets(:final count):
        if (ref.mounted) state = RoundNotEnough(count);
      case SelectedQuestions(:final streetIds):
        final byId = {for (final s in streets) s.id: s};
        final packVersion = pack.meta()['version']!;
        final roundId = await _db.startRound(
          cityId: pack.city().id,
          area: area,
          difficulty: difficulty,
          packVersion: packVersion,
          streetIds: streetIds,
        );
        if (!ref.mounted) return;
        state = RoundAsking(
          RoundContext(
            id: roundId,
            shape: shape,
            difficulty: difficulty,
            packVersion: packVersion,
            questions: [for (final id in streetIds) byId[id]!],
            index: 0,
          ),
        );
    }
  }

  Future<void> resume(String roundId) async {
    state = const RoundLoading();
    final pack = await ref.read(packRepositoryProvider.future);
    final progress = await _db.roundProgress(roundId);
    if (!ref.mounted) return;
    final area = Area.fromJson(
      jsonDecode(progress.round.areaJson) as Map<String, Object?>,
    );
    final shape = area.shapeIn(pack);
    if (shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    // Street ids are stable across pack versions; streets retired since are skipped.
    final byId = {
      for (final s in pack.streets(districtId: area.districtId)) s.id: s,
    };
    final questions = [for (final id in progress.planned) ?byId[id]];
    final answered = {for (final a in progress.answers) a.streetId};
    final index = questions.indexWhere((s) => !answered.contains(s.id));
    if (index == -1) {
      await _db.finishRound(roundId);
      if (ref.mounted) state = RoundFinished(roundId);
      return;
    }
    state = RoundAsking(
      RoundContext(
        id: roundId,
        shape: shape,
        difficulty: progress.round.difficulty,
        packVersion: pack.meta()['version']!,
        questions: questions,
        index: index,
      ),
    );
  }

  void placePin(LatLng pin) {
    if (state case RoundAsking(:final round)) state = RoundAsking(round, pin);
  }

  Future<void> confirm() async {
    if (_saving) return;
    if (state case RoundAsking(:final round, pin: final pin?)) {
      _saving = true;
      try {
        final street = round.current;
        final nearest = pointToPolylineDistance(pin, street.geometry);
        final score = scoreAnswer(
          nearest.distanceMeters,
          round.shape.areaM2,
          round.difficulty,
        );
        final answer = await _db
            .into(_db.answers)
            .insertReturning(
              AnswersCompanion.insert(
                roundId: round.id,
                streetId: street.id,
                pinLat: pin.lat,
                pinLon: pin.lon,
                distanceM: nearest.distanceMeters,
                tier: score.tier,
                xp: score.xp,
                packVersion: round.packVersion,
              ),
            );
        if (ref.mounted) {
          state = RoundRevealed(
            round,
            pin,
            answer: answer,
            nearest: nearest.nearestPoint,
          );
        }
      } finally {
        _saving = false;
      }
    }
  }

  Future<void> next() async {
    if (state case RoundRevealed(:final round)) {
      if (!round.isLast) {
        state = RoundAsking(round.advance());
        return;
      }
      await _db.finishRound(round.id);
      if (ref.mounted) state = RoundFinished(round.id);
    }
  }
}
