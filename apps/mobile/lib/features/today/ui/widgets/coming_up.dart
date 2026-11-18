import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// "Drive this run today" (board V3-10): the run Today offers, and Drive.
class DriveThisRun extends ConsumerWidget {
  const DriveThisRun({super.key, required this.run, required this.onDrive});

  final RunToDrive run;
  final VoidCallback onDrive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          const ExcludeSemantics(child: RowTile(PindoroGlyph.car)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.todayRunTitle,
                  style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                ),
                Text(
                  l10n.todayRunRoute(
                    streetName(run.ends.fromStreet, settings),
                    streetName(run.ends.toStreet, settings),
                    formatDistance(run.ends.best.lengthM, l10n),
                  ),
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          PindoroButton(
            label: l10n.todayRunDrive,
            variant: PindoroButtonVariant.secondary,
            onPressed: onDrive,
          ),
        ],
      ),
    );
  }
}

/// The road class or neighbourhood being learnt (Neighbourhood card): its mini
/// map with the streets the player knows, its seen count and bar, and what
/// comes next. [paused] while catching up. The map moves above the text at
/// large text.
class NowLearningCard extends ConsumerWidget {
  const NowLearningCard({
    super.key,
    required this.learning,
    required this.paused,
    required this.onTap,
  });

  final NowLearning learning;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final (
      :band,
      :chunk,
      :raion,
      :memory,
      :seen,
      :nextBand,
      :next,
      :outline,
      :known,
    ) = learning;
    final city = ref.watch(packRepositoryProvider).value?.city();
    String nameOf(RoadBand? band, District? chunk) => band != null
        ? l10n.roadBand(band.name)
        : chunk != null
        ? districtName(chunk, settings)
        : '';
    final name = nameOf(band, chunk);
    final total = formatNumber(memory.total);
    final where = raion != null
        ? districtName(raion, settings)
        : city == null
        ? ''
        : cityName(context, city);
    final sub = paused
        ? l10n.todayLearningPaused(where, formatNumber(seen), total)
        : l10n.todayLearningSeen(where, formatNumber(seen), total);
    final nextName = nameOf(nextBand, next);
    final nextLine = nextName.isEmpty
        ? null
        : l10n.todayLearningNext(nextName, name);
    final stack = MediaQuery.textScalerOf(context).scale(1) >= TileGrid.stackAt;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          l10n.todayNowLearning,
          style: PindoroType.labelMd.copyWith(color: c.textSecondary),
        ),
        Text(name, style: PindoroType.titleMd.copyWith(color: c.textPrimary)),
        Text(sub, style: PindoroType.bodySm.copyWith(color: c.textSecondary)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s1),
          child: MemoryBar(
            counts: memoryCountsOf(memory),
            semanticsLabel: '',
            compact: true,
          ),
        ),
        if (nextLine != null)
          Text(
            nextLine,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
      ],
    );
    final map = AreaMiniMap(area: outline, streets: known);
    return Tappable(
      onTap: onTap,
      label: [l10n.todayNowLearning, name, sub, ?nextLine].join('. '),
      child: LipBox(
        border: c.lineBase,
        padding: const EdgeInsets.all(PindoroSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s1,
          children: [
            if (stack) ...[
              map,
              text,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PindoroSpace.s3,
                children: [
                  map,
                  Expanded(child: text),
                ],
              ),
            Text(
              l10n.commonAttribution,
              style: PindoroType.labelSm.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The learning district's gateways, Solid of all.
class GatewaysCard extends StatelessWidget {
  const GatewaysCard({super.key, required this.gateways, required this.onTap});

  final GatewayCount gateways;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListGroup(
      children: [
        ListRow(
          leading: const RowTile(PindoroGlyph.route),
          title: l10n.todayGateways(
            formatNumber(gateways.solid),
            formatNumber(gateways.total),
          ),
          subtitle: l10n.todayGatewaysSubtitle,
          trailing: const PindoroIcon(PindoroGlyph.chevronRight),
          onTap: onTap,
        ),
      ],
    );
  }
}

/// Yesterday's mix-ups, each pair on a Miss-tinted row.
class WatchOut extends ConsumerWidget {
  const WatchOut(this.pairs, {super.key});

  final List<(NamedStreet, NamedStreet)> pairs;

  static const int _shown = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = PindoroTheme.of(context);
    final miss = theme.tier(Tier.miss);
    final settings = ref.watch(settingsProvider).value;
    return ListGroup(
      children: [
        for (final (a, b) in pairs.take(_shown))
          ListRow(
            leading: RowTile(
              PindoroGlyph.reroute,
              face: miss.bg,
              ink: miss.ink,
            ),
            title: '${streetName(a, settings)} ↔ ${streetName(b, settings)}',
            subtitle: l10n.todayMixedUpYesterday,
          ),
      ],
    );
  }
}

/// Catching up's info card: why most overdue comes first.
class MostOverdueFirst extends StatelessWidget {
  const MostOverdueFirst({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: PindoroSpace.s3,
        children: [
          const ExcludeSemantics(child: RowTile(PindoroGlyph.info)),
          Expanded(
            child: Text(
              context.l10n.todayBacklogInfo,
              style: PindoroType.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
