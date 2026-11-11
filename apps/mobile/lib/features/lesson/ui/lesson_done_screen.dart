import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/badges/ui/badge_reward.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/lesson_title.dart';
import 'package:pindoro/features/lesson/data/lesson_done_data.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/level_row.dart';
import 'package:pindoro/features/progress/ui/level_up_screen.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// When each part of the arrival starts (canvas R4-24: Pindo pops, the XP
/// counts up, the tiles stagger, the bar fills, the chips pop).
abstract final class _Arrival {
  static const Duration reward = Duration(milliseconds: 200);
  static const Duration tiles = Duration(milliseconds: 1100);
  static const Duration bar = Duration(milliseconds: 1250);
  static const Duration chips = Duration(milliseconds: 1700);
}

/// Lesson complete (canvas R4-24): the XP, accuracy, streets and time, the
/// level bar, the streak; Continue (or back) returns to the Path.
class LessonDoneScreen extends ConsumerStatefulWidget {
  const LessonDoneScreen({super.key, required this.resultId});

  final String resultId;

  @override
  ConsumerState<LessonDoneScreen> createState() => _LessonDoneScreenState();
}

class _LessonDoneScreenState extends ConsumerState<LessonDoneScreen>
    with BadgeMoments {
  bool _levelUpOpened = false;

  /// Back to the Path, which plays the unlock from the stop just finished
  /// (practice finishes none).
  void _continue(LessonResult r) {
    if (r.kind != LessonKind.practice) {
      ref.read(pathUnlockProvider.notifier).play((
        unitId: r.unitId,
        kind: r.kind == LessonKind.pitStop ? StopKind.pitStop : StopKind.lesson,
        lesson: r.lesson,
      ));
    }
    context.go(Routes.path);
  }

  /// A level crossed in this lesson opens the level-up moment once; the
  /// badges' sheets follow it.
  void _levelUp(int level, int totalXp) {
    if (_levelUpOpened) return;
    _levelUpOpened = true;
    unawaited(
      showLevelUpAfter(
        context,
        ref,
        level: level,
        totalXp: totalXp,
        delay: _Arrival.chips,
      ).then((_) => showBadgesAfter(Duration.zero)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = ref.watch(lessonDoneProvider(widget.resultId)).value;
    if (done == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final r = done.result;
    final lesson = done.lesson;
    final unit = done.unit;
    final before = progressWithinLevel(done.totalXp - r.xp);
    final after = progressWithinLevel(done.totalXp);
    if (after.level > before.level) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _levelUp(after.level, done.totalXp),
      );
    } else {
      showBadgesAfter(_Arrival.chips);
    }
    final streak = ref.watch(streakProvider).value?.summary.days ?? 0;
    final accuracy = r.tests == 0 ? 0 : (r.rightFirst * 100 / r.tests).round();
    final time = Duration(milliseconds: r.durationMs);
    final isLesson = r.kind == LessonKind.lesson;
    final title = switch (r.kind) {
      LessonKind.pitStop => l10n.lessonDonePitStopTitle,
      LessonKind.practice => l10n.lessonDonePracticeTitle,
      LessonKind.lesson when r.perfect => l10n.lessonDonePerfectTitle,
      // A Final drive opens Unit complete and placement opens nothing.
      LessonKind.lesson ||
      LessonKind.finalDrive ||
      LessonKind.placed => l10n.lessonDoneTitle,
    };
    final subtitle = lesson != null
        ? l10n.lessonDoneLesson(
            lesson.number,
            lessonTitle(l10n, lesson, settings),
          )
        : unit != null
        ? l10n.lessonDoneUnit(
            unit.number,
            districtName(unit.district, settings),
          )
        : null;
    final finish = formatNumber(LessonRules.finishXp);
    final bonus = !isLesson
        ? null
        : r.perfect
        ? l10n.lessonDoneBonusPerfect(
            finish,
            formatNumber(LessonRules.perfectXp),
          )
        : l10n.lessonDoneBonusFixes(
            done.fixes,
            finish,
            formatNumber(done.fixXp),
          );
    final tiles = [
      StatTile(
        glyph: PindoroGlyph.target,
        label: l10n.lessonStatAccuracy,
        value: l10n.lessonPercent(formatNumber(accuracy)),
      ),
      StatTile(
        glyph: PindoroGlyph.signpost,
        label: isLesson ? l10n.lessonStatNewStreets : l10n.lessonStatStreets,
        value: formatNumber(
          isLesson ? lesson?.streets.length ?? done.streets : done.streets,
        ),
      ),
      StatTile(
        glyph: PindoroGlyph.timer,
        label: l10n.lessonStatTime,
        value: l10n.lessonClock(
          '${time.inMinutes}',
          time.inSeconds.remainder(60).toString().padLeft(2, '0'),
        ),
      ),
    ];

    final page = PageScaffold(
      title: title,
      showBack: false,
      footer: PindoroButton(
        label: l10n.commonContinue,
        onPressed: () => _continue(r),
      ),
      children: [
        if (subtitle != null)
          Text(
            subtitle,
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
        Row(
          spacing: PindoroSpace.s3,
          children: [
            PopIn(
              child: Pindo(
                r.perfect ? PindoExpression.cheering : PindoExpression.proud,
                height: 64,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PindoroSpace.s1,
                children: [
                  PopIn(
                    delay: _Arrival.reward,
                    child: CountUp(
                      value: r.xp,
                      delay: _Arrival.reward,
                      onEnd: ref.read(feedbackProvider).reward,
                      builder: (context, xp) => RewardTotal(
                        value: l10n.commonXp(formatNumber(xp)),
                        semanticLabel: l10n.a11yLessonReward(
                          formatNumber(r.xp),
                        ),
                      ),
                    ),
                  ),
                  if (bonus != null)
                    Text(
                      bonus,
                      style: PindoroType.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              for (final (i, tile) in tiles.indexed)
                Expanded(
                  child: RiseIn(
                    delay: _Arrival.tiles + PindoroMotion.stagger * i,
                    distance: PindoroSpace.s4,
                    child: tile,
                  ),
                ),
            ],
          ),
        ),
        LevelRow(
          level: after,
          from: after.level > before.level ? 0 : before.fraction,
          delay: _Arrival.bar,
        ),
        if (done.grewStreak || after.level > before.level)
          Wrap(
            spacing: PindoroSpace.s2,
            runSpacing: PindoroSpace.s2,
            children: [
              if (done.grewStreak)
                PopIn(
                  delay: _Arrival.chips,
                  child: Pill(
                    label: l10n.streakDays(formatNumber(streak)),
                    icon: PindoroGlyph.flame,
                    iconColor: c.streakFlame,
                    iconAccent: c.streakCore,
                    semanticLabel: l10n.resultsStreakA11y(formatNumber(streak)),
                  ),
                ),
              if (after.level > before.level)
                PopIn(
                  delay: _Arrival.chips,
                  child: Pill(
                    label: l10n.levelUpTitle(after.level),
                    icon: PindoroGlyph.xp,
                    iconColor: c.xpFill,
                  ),
                ),
            ],
          ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _continue(r);
      },
      child: Stack(
        children: [
          page,
          Positioned.fill(
            child: Celebration(
              size: r.perfect ? CelebrationSize.big : CelebrationSize.medium,
              burstCenter: const Alignment(-0.6, -0.6),
            ),
          ),
        ],
      ),
    );
  }
}
