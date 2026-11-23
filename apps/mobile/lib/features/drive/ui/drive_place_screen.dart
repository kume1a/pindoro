import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/navigation.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Where you are, for the search's distances; null without a fix.
final _hereProvider = FutureProvider.autoDispose<LatLng?>((ref) async {
  final located = await ref.watch(locationServiceProvider).locate();
  return located is Located ? located.position : null;
});

/// Home ([home]) or Work for drives (SPEC §16.23 items 120–121): the street or place picked
/// from the search, kept apart from the learning neighbourhoods.
class DrivePlaceScreen extends ConsumerWidget {
  const DrivePlaceScreen({required this.home, super.key});

  final bool home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final anchors = ref.watch(drivePlacesProvider).value;
    final current = home ? anchors?.home : anchors?.work;
    final here = ref.watch(_hereProvider).value;
    Future<void> save(DriveTarget? target) async {
      final pack = await ref.read(packRepositoryProvider.future);
      final place = target == null
          ? null
          : drivePlaceOf(target, pack.junctionNodes());
      await ref
          .read(settingsDaoProvider)
          .setDrivePlace(
            place == null ? null : encodeDrivePlace(place),
            home: home,
          );
      if (context.mounted) popIfCurrent(context);
    }

    Future<void> pick(DriveDest dest) async {
      final graph = await ref.read(drivingGraphProvider.future);
      final streets = await ref.read(cityStreetsProvider.future);
      if (graph == null) return;
      final target = resolveDest(graph, streets, dest, here: here);
      if (target != null) await save(target);
    }

    return PageScaffold(
      title: home ? l10n.drivePlaceHome : l10n.drivePlaceWork,
      children: [
        Text(
          l10n.drivePlaceNote,
          style: PindoroType.bodyMd.copyWith(
            color: PindoroTheme.of(context).colors.textSecondary,
          ),
        ),
        if (current != null)
          ListGroup(
            children: [
              ListRow(
                leading: RowTile(
                  home ? PindoroGlyph.home : PindoroGlyph.briefcase,
                ),
                title: targetName(current, settings),
                trailing: PindoroButton(
                  label: l10n.drivePlaceClear,
                  variant: PindoroButtonVariant.tertiary,
                  onPressed: () => unawaited(save(null)),
                ),
              ),
            ],
          ),
        DestinationSearch(
          here: here,
          onPick: (dest) => unawaited(pick(dest)),
          quick: [
            ChooseOnMapRow(
              pick: MapPick.place,
              onPick: (dest) => unawaited(pick(dest)),
            ),
          ],
        ),
      ],
    );
  }
}
