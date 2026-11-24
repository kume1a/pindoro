import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/navigation.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A stop on the way or a new destination (SPEC §16.23 item 134), picked on a screen of its own;
/// null when cancelled.
Future<DriveDest?> pickRoutePlace(BuildContext context, MapPick pick) =>
    Navigator.of(context).push<DriveDest>(
      MaterialPageRoute(
        builder: (_) => inThemeOf(context, RoutePlaceScreen(pick: pick)),
      ),
    );

/// Add stop and Change destination (item 134): the search focused, Cancel beside it; with
/// nothing typed, Choose on the map, Home and Work with the minutes there, and Recent. A pick
/// pops with it. During a drive it stays open at any speed (a passenger picks), and closes
/// when the drive ends.
class RoutePlaceScreen extends ConsumerWidget {
  const RoutePlaceScreen({required this.pick, super.key});

  /// [MapPick.stop] or [MapPick.drive] (a destination).
  final MapPick pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    ref.listen(driveControllerProvider, (before, next) {
      if (before is DriveRecording && next is! DriveRecording) {
        popIfCurrent(context);
      }
    });
    final here = switch (ref.watch(driveControllerProvider)) {
      final DriveRecording r => r.view?.at ?? r.start,
      final DriveSetup s => s.here,
      _ => null,
    };
    final places = ref.watch(drivePlacesProvider).value;
    void done(DriveDest dest) => Navigator.of(context).pop(dest);
    ListRow anchor(PindoroGlyph glyph, String title, DriveTarget place) =>
        ListRow(
          leading: RowTile(glyph),
          title: title,
          subtitle: targetName(place, settings),
          trailing: _Minutes(place),
          onTap: () => done((
            street: place.street,
            place: place.place,
            junction: place.junction,
            at: place.at,
          )),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PindoroSpace.s4),
          children: [
            DestinationSearch(
              here: here,
              onPick: done,
              autofocus: true,
              placeholder: pick == MapPick.stop ? l10n.driveAddStop : null,
              trailing: PindoroButton(
                label: l10n.commonCancel,
                variant: PindoroButtonVariant.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              quick: [
                ChooseOnMapRow(pick: pick, onPick: done),
                if (places?.home case final home?)
                  anchor(PindoroGlyph.home, l10n.driveHome, home),
                if (places?.work case final work?)
                  anchor(PindoroGlyph.briefcase, l10n.driveWork, work),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The car's minutes to [place] from where the phone is, by the way a drive would take.
class _Minutes extends ConsumerWidget {
  const _Minutes(this.place);

  final DriveTarget place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(driveMinutesProvider(place)).value;
    if (minutes == null) return const PindoroIcon(PindoroGlyph.chevronRight);
    final c = PindoroTheme.of(context).colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: PindoroSpace.s1,
      children: [
        PindoroIcon(
          PindoroGlyph.car,
          size: PindoroSize.iconSm,
          color: c.textSecondary,
        ),
        Text(
          context.l10n.unitMinutes(minutes),
          style: PindoroType.labelLg.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}
