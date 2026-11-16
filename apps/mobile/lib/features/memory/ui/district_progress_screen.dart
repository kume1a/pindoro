import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Progress, one district (board V3-60 `district`): its memory and its
/// neighbourhoods in teaching order.
class DistrictProgressScreen extends ConsumerWidget {
  const DistrictProgressScreen({super.key, required this.id});

  /// The raion's id.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final raion = ref
        .watch(progressProvider)
        .value
        ?.districts
        .where((d) => d.district.id == id)
        .firstOrNull;
    if (raion == null) {
      return const PageScaffold(children: [Center(child: LaneLoader())]);
    }
    final name = districtName(raion.district, settings);
    final m = raion.memory;
    return PageScaffold(
      title: name,
      children: [
        Text(
          l10n.progressInMemory(
            formatNumber(m.memory.round()),
            formatNumber(m.total),
          ),
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        MemoryBar(
          counts: memoryCountsOf(m),
          semanticsLabel: memoryBarLabel(l10n, name, m),
          animate: !MediaQuery.disableAnimationsOf(context),
        ),
        MemoryLegend(
          counts: memoryCountsOf(m),
          names: memoryNames(l10n),
          format: formatNumber,
        ),
        SectionTitle(l10n.progressNeighbourhoods),
        ListGroup(
          children: [
            for (final chunk in raion.chunks)
              _chunkRow(
                l10n,
                c,
                chunk,
                districtName(chunk.chunk, settings),
                switch (chunk.after) {
                  final a? => districtName(a, settings),
                  null => null,
                },
              ),
          ],
        ),
        Text(
          l10n.progressMasteredMeans,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }

  Widget _chunkRow(
    AppLocalizations l10n,
    PindoroColors c,
    ChunkProgress chunk,
    String name,
    String? after,
  ) {
    final total = formatNumber(chunk.memory.total);
    final seen = formatNumber(chunk.seen);
    final (tile, subtitle) = switch (chunk.stage) {
      ChunkStage.mastered => (
        RowTile(
          PindoroGlyph.checkCircle,
          face: c.primaryBase,
          ink: c.primaryOn,
        ),
        l10n.progressChunkMastered(total),
      ),
      ChunkStage.now => (
        const RowTile(PindoroGlyph.play),
        l10n.progressChunkNow(seen, total),
      ),
      ChunkStage.started => (
        const RowTile(PindoroGlyph.play),
        l10n.progressChunkSeen(seen, total),
      ),
      ChunkStage.next => (
        RowTile(PindoroGlyph.lock, face: c.surfaceSunken, ink: c.textSecondary),
        after == null
            ? l10n.progressChunkStreets(total)
            : l10n.progressChunkAfter(after, total),
      ),
    };
    final bar = memoryBarLabel(l10n, name, chunk.memory);
    return ListRow(
      leading: tile,
      title: name,
      subtitle: subtitle,
      below: chunk.stage == ChunkStage.next
          ? null
          : MemoryBar(
              counts: memoryCountsOf(chunk.memory),
              semanticsLabel: bar,
              compact: true,
            ),
      semanticsLabel: '$name. $subtitle. $bar',
    );
  }
}
