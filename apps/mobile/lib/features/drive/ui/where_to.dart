import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Where to (board V32-10, the Drive tab; SPEC §16.23 item 129): the search, Home and Work as
/// tiles with the minutes there, today's run on a day with one, Surprise me, Recent, and
/// [below] under them while nothing is typed. [here] (else where the phone is, if location is
/// allowed) gives the rows their distance.
class WhereTo extends ConsumerWidget {
  const WhereTo({
    required this.onChoose,
    required this.onPick,
    this.here,
    this.below = const [],
    super.key,
  });

  final ValueChanged<DriveTo> onChoose;
  final ValueChanged<DriveDest> onPick;
  final LatLng? here;
  final List<Widget> below;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final run = ref.watch(todayRunProvider).value;
    final anchors = ref.watch(drivePlacesProvider).value;
    final near = ref.watch(driveHereProvider).value;
    Widget tile(DriveTo to, DriveTarget? place, int? minutes) {
      final home = to == DriveTo.home;
      final glyph = home ? PindoroGlyph.home : PindoroGlyph.briefcase;
      final label = home ? l10n.driveHome : l10n.driveWork;
      if (place == null) {
        return StatTile(
          glyph: glyph,
          label: label,
          value: home ? l10n.driveSetHome : l10n.driveSetWork,
          onTap: () => unawaited(
            context.push(Routes.drivePlaceOf(home ? 'home' : 'work')),
          ),
        );
      }
      final name = targetName(place, settings);
      return StatTile(
        glyph: glyph,
        label: label,
        value: minutes == null ? name : l10n.unitMinutes(minutes),
        caption: minutes == null ? null : name,
        onTap: () => onChoose(to),
      );
    }

    final scale = MediaQuery.textScalerOf(context).scale(1);
    return DestinationSearch(
      here: here ?? near?.here,
      onPick: onPick,
      above: [
        TileGrid(columns: scale >= TileGrid.stackAt ? 1 : 2, [
          tile(DriveTo.home, anchors?.home, near?.home),
          tile(DriveTo.work, anchors?.work, near?.work),
        ]),
      ],
      quick: [
        if (run != null)
          ListRow(
            leading: const RowTile(PindoroGlyph.car),
            title: l10n.driveTodaysRun,
            subtitle: runLine(l10n, run, (s) => streetName(s, settings)),
            trailing: const PindoroIcon(PindoroGlyph.chevronRight),
            onTap: () => onChoose(DriveTo.run),
          ),
        ChooseOnMapRow(onPick: onPick),
        ListRow(
          leading: const RowTile(PindoroGlyph.compass),
          title: l10n.driveSurprise,
          subtitle: l10n.driveSurpriseNote,
          trailing: const PindoroIcon(PindoroGlyph.chevronRight),
          onTap: () => onChoose(DriveTo.surprise),
        ),
      ],
      below: below,
    );
  }
}

/// "Paliashvili St → Tamarashvili St · 2.4 km".
String runLine(
  AppLocalizations l10n,
  RunToDrive run,
  String Function(NamedStreet) name,
) => l10n.todayRunRoute(
  name(run.ends.fromStreet),
  name(run.ends.toStreet),
  formatDistance(run.ends.best.lengthM, l10n),
);
