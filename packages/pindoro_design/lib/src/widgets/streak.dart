import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'motion.dart';
import 'round_hud.dart';
import 'tappable.dart';

/// The streak in the Home top bar: flame and days in the look of [state]
/// (component Streak § Counter states). The tap target is at least 48 dp.
class StreakPill extends StatelessWidget {
  const StreakPill({
    super.key,
    required this.label,
    required this.state,
    required this.semanticLabel,
    this.onPressed,
  });

  final String label;
  final StreakPillState state;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final pill = switch (state) {
      StreakPillState.active => Pill(
        label: label,
        icon: PindoroGlyph.flame,
        iconColor: c.streakFlame,
        iconAccent: c.streakCore,
      ),
      StreakPillState.off => Pill(
        label: label,
        icon: PindoroGlyph.flame,
        iconColor: c.pathNodeLockedIcon,
        iconAccent: c.pathNodeLockedFill,
        foreground: c.textSecondary,
      ),
      StreakPillState.atRisk => Pill(
        label: label,
        icon: PindoroGlyph.flame,
        iconColor: c.warningText,
        face: c.warningSoft,
        lip: c.warningLip,
        foreground: c.warningText,
      ),
      StreakPillState.frozen => Pill(
        label: label,
        icon: PindoroGlyph.freeze,
        iconColor: c.streakFreezeInk,
        face: c.streakFreezeFill,
        lip: PindoroPalette.aqua400,
        foreground: c.streakFreezeInk,
      ),
    };
    return Tappable(
      onTap: onPressed,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: PindoroSize.tapMin),
        child: Center(widthFactor: 1, child: pill),
      ),
    );
  }
}

/// Today's XP toward the daily goal: a [stroke] ring (`color.xp.track` under
/// `color.xp.fill`) around the flame, full when the goal is met. A new
/// [progress] animates over `duration.slow`.
class DailyGoalRing extends StatelessWidget {
  const DailyGoalRing({
    super.key,
    required this.progress,
    required this.semanticLabel,
    this.size = 56,
    this.stroke = 9,
  });

  /// 0–1.
  final double progress;
  final String semanticLabel;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (duration, curve) = delayedMotion(
      context,
      Duration.zero,
      PindoroMotion.durationSlow,
      PindoroMotion.easeStandard,
    );
    return Semantics(
      label: semanticLabel,
      container: true,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress.clamp(0, 1)),
          duration: duration,
          curve: curve,
          builder: (_, v, child) => CustomPaint(
            painter: _RingPainter(
              value: v,
              stroke: stroke,
              track: c.xpTrack,
              fill: c.xpFill,
            ),
            child: child,
          ),
          child: Center(
            child: PindoroIcon(
              PindoroGlyph.flame,
              color: c.streakFlame,
              accent: c.streakCore,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint
        ..color = fill
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      old.fill != fill;
}

/// How a day shows in [StreakCalendar].
enum StreakDay {
  /// Goal met: `color.streak.day.done`.
  met,

  /// Covered by a freeze: `color.streak.freeze.fill`.
  frozen,

  /// Past (or today) and not met: `color.streak.day.empty`.
  missed,

  /// Before the first goal day, or still ahead: plain text.
  plain,
}

/// A month of the streak (`.pd-cal`): seven columns starting on
/// [firstWeekday] (`DateTime.monday` … `DateTime.sunday`), 36 dp day discs
/// 6 dp apart, [today] ringed in `color.primary.base`. Screen readers get it
/// as one image described by [semanticLabel].
class StreakCalendar extends StatelessWidget {
  const StreakCalendar({
    super.key,
    required this.month,
    required this.dayState,
    required this.weekdays,
    required this.semanticLabel,
    this.today,
    this.firstWeekday = DateTime.monday,
  });

  /// Any date in the month shown.
  final DateTime month;
  final StreakDay Function(int day) dayState;

  /// Seven narrow weekday names, Monday first.
  final List<String> weekdays;
  final String semanticLabel;

  /// The day of the month to ring; null when today isn't in [month].
  final int? today;
  final int firstWeekday;

  static const double _disc = 36;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = (DateTime(month.year, month.month).weekday - firstWeekday) % 7;
    final cells = <Widget>[
      for (var i = 0; i < 7; i++)
        SizedBox(
          width: _disc,
          height: 20,
          child: Center(
            child: Text(
              weekdays[(firstWeekday - 1 + i) % 7],
              style: PindoroType.labelSm.copyWith(color: c.textSecondary),
            ),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.square(dimension: _disc),
      for (var d = 1; d <= days; d++) _day(c, d),
    ];
    return Semantics(
      label: semanticLabel,
      container: true,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: 7 * _disc + 6 * _gap,
        child: Wrap(spacing: _gap, runSpacing: _gap, children: cells),
      ),
    );
  }

  Widget _day(PindoroColors c, int day) {
    final (Color? face, Color text) = switch (dayState(day)) {
      StreakDay.met => (c.streakDayDone, c.warningOn),
      StreakDay.frozen => (c.streakFreezeFill, c.streakFreezeInk),
      StreakDay.missed => (c.streakDayEmpty, c.textSecondary),
      StreakDay.plain => (null, c.textDisabled),
    };
    final isToday = day == today;
    return Container(
      width: _disc,
      height: _disc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: face,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(
                color: c.primaryBase,
                width: PindoroStroke.thick,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: Text(
        '$day',
        style: PindoroType.labelMd.copyWith(
          color: isToday ? c.textPrimary : text,
        ),
      ),
    );
  }
}

/// The streak freeze card (`.pd-freeze`): the freeze icon, [title] and [body]
/// in `color.streak.freeze.ink` on `color.streak.freeze.fill`.
class StreakFreezeCard extends StatelessWidget {
  const StreakFreezeCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      decoration: BoxDecoration(
        color: c.streakFreezeFill,
        borderRadius: BorderRadius.circular(PindoroRadius.xl),
      ),
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          PindoroIcon(
            PindoroGlyph.freeze,
            size: PindoroSize.iconLg,
            color: c.streakFreezeInk,
            cut: c.streakFreezeFill,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: PindoroType.titleSm.copyWith(color: c.streakFreezeInk),
                ),
                Text(
                  body,
                  style: PindoroType.bodySm.copyWith(color: c.streakFreezeInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
