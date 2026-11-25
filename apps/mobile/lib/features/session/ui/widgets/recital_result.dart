import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/dialogs.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/session/ui/session_state.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A checked recital (RecitalScreen's result): the drawn or typed route against the best one,
/// its turns, practice and "Report this turn".
class RecitalResultView extends StatelessWidget {
  const RecitalResultView({
    super.key,
    required this.play,
    required this.task,
    required this.graded,
    required this.graph,
    required this.streets,
    required this.settings,
    required this.map,
    required this.topBar,
    required this.onNext,
    required this.onReport,
    this.chip,
  });

  final SessionPlaying play;
  final RecitalTask task;
  final RecitalResult graded;
  final RoadGraph graph;
  final Map<String, NamedStreet> streets;
  final Settings? settings;
  final Widget Function(PindoroMap map) map;
  final Widget topBar;
  final Widget? chip;
  final Future<void> Function() onNext;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final path = graded.path;
    final best = graded.best;
    final illegal = graded.illegal;
    // A way with no name is "a link road", never a blank in the sentence.
    String nameOf(RoadEdge? e) => switch (streets[e?.streetId]) {
      final s? => streetName(s, settings),
      null => l10n.debriefLinkRoad,
    };
    final extraM = graded.extraM ?? 0;
    final mapChip = switch (illegal) {
      final m? => (
        at: _middle(m.edge.line),
        label: m.reason == IllegalReason.oneway
            ? l10n.recitalOnewayChip
            : l10n.recitalNoTurnChip,
      ),
      null when graded.divergence != null && extraM >= 1 => (
        at: graph.at(graded.divergence!),
        label: '+${formatDistance(extraM, l10n)}',
      ),
      null => null,
    };
    final turns = [
      for (final d in graded.decisions)
        if (d.newStreet && d.turn != null) d,
    ];
    final right = graded.decisions.where((d) => d.correct).length;
    final stretch = graded.stretch;
    final sentence = switch (illegal) {
      final m? when m.reason == IllegalReason.oneway => l10n.recitalOneway(
        nameOf(m.edge),
      ),
      final m? => l10n.recitalNoTurn(nameOf(m.approach), nameOf(m.edge)),
      null when path == null => l10n.recitalNoRoute,
      null when stretch == null => l10n.recitalNotThere,
      null => [
        if (extraM < 1)
          l10n.recitalBestDrive
        else
          l10n.recitalExtra(formatDistance(extraM, l10n)),
        if (graded.decisions.isNotEmpty)
          l10n.recitalTurnsMatch(
            formatNumber(right),
            formatNumber(graded.decisions.length),
          ),
      ].join(' '),
    };
    final label = illegal != null
        ? l10n.recitalNotDrivable
        : stretch != null && extraM >= 1 && graded.tier != Tier.miss
        ? l10n.recitalLonger(
            tierWord(l10n, graded.tier),
            formatNumber(((stretch - 1) * 100).round()),
          )
        : null;
    final a = graph.at(task.from);
    final b = graph.at(task.to);
    return TaskScaffold(
      topBar: topBar,
      header: const SizedBox.shrink(),
      map: (insets) => map(
        PindoroMap(
          area: play.area,
          frame: [
            a,
            b,
            for (final line in [...?best?.lines, ...?path?.lines]) ...line,
          ],
          route: (
            a: a,
            b: b,
            drawn: path?.lines ?? const [],
            track: const [],
            best: best?.lines ?? const [],
            turn: const [],
            chip: mapChip,
            reached: true,
          ),
          names: MapNames.all,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      overlays: [
        Positioned.fill(
          child: Semantics(
            container: true,
            label: l10n.a11yRecitalMap,
            child: const SizedBox.expand(),
          ),
        ),
      ],
      result: TaskResult(
        resultKey: play.index,
        tier: graded.tier,
        label: label,
        chip: chip,
        sentence: sentence,
        onNext: onNext,
        chips: [
          for (final d in turns)
            _DecisionRow(
              tier: d.correct ? Tier.great : Tier.close,
              title: recitalOntoLabel(l10n, d.turn, nameOf(d.exit)),
              subtitle: d.correct
                  ? l10n.recitalOnBest
                  : graph
                        .legalExits(d.junction, approach: d.approach)
                        .any((e) => e.id == d.exit.id)
                  ? l10n.recitalDetour
                  : l10n.recitalWrongWay,
            ),
          if (task.practice.isNotEmpty)
            StatChip(
              label: l10n.recitalPractice(task.practice.length),
              glyph: PindoroGlyph.retry,
            ),
          if (illegal != null)
            task.reported
                ? StatChip(
                    label: l10n.recitalReported,
                    glyph: PindoroGlyph.check,
                  )
                : Tappable(
                    onTap: () => unawaited(_report(context)),
                    label: l10n.recitalReport,
                    child: StatChip(
                      label: l10n.recitalReport,
                      glyph: PindoroGlyph.flag,
                    ),
                  ),
        ],
      ),
    );
  }

  /// Report this turn, once asked: it makes the move legal on this phone for good.
  Future<void> _report(BuildContext context) async {
    final l10n = context.l10n;
    final report = await askChoice(
      context,
      title: l10n.recitalReportTitle,
      body: l10n.recitalReportBody,
      primary: l10n.commonCancel,
      secondary: l10n.recitalReportConfirm,
    );
    if (report && context.mounted) onReport();
  }
}

LatLng _middle(Polyline line) => line[line.length ~/ 2];

String recitalOntoLabel(AppLocalizations l10n, Turn? turn, String place) =>
    switch (turn) {
      Turn.left => l10n.recitalLeftOnto(place),
      Turn.right => l10n.recitalRightOnto(place),
      Turn.straight => l10n.recitalStraightOnto(place),
      Turn.uTurn => l10n.recitalUTurnOnto(place),
      null => l10n.recitalThen(place),
    };

/// One turn of a graded recital: its tier icon, "Left onto X" and whether
/// it was on the best route.
class _DecisionRow extends StatelessWidget {
  const _DecisionRow({
    required this.tier,
    required this.title,
    required this.subtitle,
  });

  final Tier tier;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return SizedBox(
      width: double.infinity,
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          TierBadge(tier, size: PindoroSize.iconMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                ),
                Text(
                  subtitle,
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
