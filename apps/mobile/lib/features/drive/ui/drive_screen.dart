import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/debrief_screen.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/drive_recording_view.dart';
import 'package:pindoro/features/drive/ui/where_to.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/drive_week_card.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A drive (DriveScreen `setup`, `recording`; boards V3-50 and V32-10 to
/// V32-50): pick where to and how much help, drive with the voice by level
/// and nothing to tap while moving; once parked, the debrief.
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({this.to, this.dest, super.key});

  /// [Routes.drive]'s screen: `?to=` a [DriveTo] by name, or a street or place as `extra`.
  factory DriveScreen.route(GoRouterState state) {
    final to = DriveTo.values.asNameMap()[state.uri.queryParameters['to']];
    return DriveScreen(
      to: to == DriveTo.own ? null : to,
      dest: state.extra as DriveDest?,
    );
  }

  /// A destination chosen before the screen opened (the Drive tab, Today's run).
  final DriveTo? to;

  /// A street or place chosen before the screen opened; wins over [to].
  final DriveDest? dest;

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  /// Until the destination given on opening is chosen, after the first frame.
  late bool _choosing = widget.to != null || widget.dest != null;

  @override
  void initState() {
    super.initState();
    if (!_choosing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(driveControllerProvider.notifier);
      switch ((widget.dest, widget.to)) {
        case (final dest?, _):
          controller.pickOwn(dest);
        case (_, final to?):
          controller.choose(to);
        case _:
      }
      setState(() => _choosing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    void leave() =>
        context.canPop() ? context.pop() : context.go(Routes.driveTab);
    final state = ref.watch(driveControllerProvider);
    if (_choosing) return const Scaffold();
    return switch (state) {
      final DriveSetup s when s.to == null => _Search(setup: s),
      final DriveSetup s => _Setup(setup: s),
      final DriveRecording r => DriveRecordingView(recording: r),
      final DriveReview r => DebriefScreen(id: r.id!, onDone: leave),
    };
  }
}

/// Where to (DriveSetup `search`), for a new destination from the stopped bar's Route or the
/// setup's Change: the Drive tab's [WhereTo] choosing in place.
class _Search extends ConsumerWidget {
  const _Search({required this.setup});

  final DriveSetup setup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(driveControllerProvider.notifier);
    return PageScaffold(
      title: l10n.driveTitle,
      children: [
        if (setup.denied case final denied?)
          ListRow(
            leading: const RowTile(PindoroGlyph.locateOff),
            title: l10n.driveNoLocation,
            onTap: () => unawaited(
              ref.read(locationServiceProvider).openSettings(denied),
            ),
          ),
        WhereTo(
          here: setup.here,
          onChoose: controller.choose,
          onPick: controller.pickOwn,
        ),
      ],
    );
  }
}

/// A destination chosen (DriveSetup `chosen`, `todaysRun`): where to and how
/// far, the suggested level with its reason, the picker and what the level
/// does, the week's goal; Preview (V32-11) and Start.
class _Setup extends ConsumerWidget {
  const _Setup({required this.setup});

  final DriveSetup setup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final controller = ref.read(driveControllerProvider.notifier);
    final run = ref.watch(todayRunProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final to = setup.to!;
    final target = setup.target;
    final plan = setup.suggestion?.plan;
    String name(NamedStreet s) => streetName(s, settings);
    final ready = target != null || (to == DriveTo.run && run != null);
    Widget rule(PindoroGlyph glyph, String title, String note) =>
        ListRow(leading: RowTile(glyph), title: title, subtitle: note);
    final denied = setup.denied;
    final title = switch (to) {
      DriveTo.run => l10n.driveTodaysRun,
      DriveTo.home => l10n.driveHome,
      DriveTo.work => l10n.driveWork,
      _ when target != null => targetName(target, settings),
      DriveTo.surprise => l10n.driveSurprise,
      DriveTo.own => switch (setup.own) {
        (street: final s?, place: _, junction: _) => name(s),
        (street: _, place: final p?, junction: _) => placeLabel(p, settings),
        _ => l10n.driveTitle,
      },
    };
    final line = switch ((to, run)) {
      (DriveTo.run, final run?) => runLine(l10n, run, name),
      _ => [
        if (target != null && graph != null)
          const PlaceLine().of(context, ref, graph.at(target.junction)),
        if (plan != null) ...[
          formatDistance(plan.route.lengthM, l10n),
          l10n.driveAboutMin((plan.seconds / 60).ceil()),
        ],
      ].where((s) => s.isNotEmpty).join(' · '),
    };
    return PageScaffold(
      title: l10n.driveTitle,
      footer: Row(
        spacing: PindoroSpace.s3,
        children: [
          Expanded(
            child: PindoroButton(
              label: l10n.previewButton,
              variant: PindoroButtonVariant.secondary,
              onPressed: ready && setup.suggestion != null
                  ? () => unawaited(context.push(Routes.drivePreview))
                  : null,
            ),
          ),
          Expanded(
            child: PindoroButton(
              label: l10n.driveStart,
              icon: PindoroGlyph.car,
              onPressed: ready
                  ? () => unawaited(
                      controller.start(
                        title: l10n.driveNotificationTitle,
                        text: l10n.driveNotificationText,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
      children: [
        ListGroup(
          children: [
            ListRow(
              leading: RowTile(_glyph(to, target)),
              title: title,
              subtitle: line.isEmpty ? null : line,
              trailing: PindoroIconButton(
                glyph: PindoroGlyph.edit,
                semanticLabel: l10n.driveChangeDest,
                onPressed: controller.clear,
              ),
            ),
          ],
        ),
        if (denied != null || setup.noTarget)
          ListRow(
            leading: RowTile(
              denied == null && to == DriveTo.surprise
                  ? PindoroGlyph.info
                  : PindoroGlyph.locateOff,
            ),
            title: denied != null
                ? l10n.driveNoLocation
                : switch (to) {
                    DriveTo.run => l10n.driveNoRun,
                    DriveTo.surprise => l10n.driveNoSurprise,
                    _ => l10n.driveNoTarget,
                  },
            subtitle: denied == null && to == DriveTo.surprise
                ? l10n.driveNoSurpriseWhy
                : null,
            onTap: denied == null
                ? null
                : () => unawaited(
                    ref.read(locationServiceProvider).openSettings(denied),
                  ),
          ),
        SectionTitle(l10n.driveLevelTitle),
        if (to == DriveTo.run)
          LevelSuggestion(
            lead: l10n.driveRunLead,
            level: l10n.driveStartsAt(levelLabel(l10n, DriveLevel.off)),
            reason: l10n.driveEveryLevel,
          )
        else if (setup.suggestion case final s?)
          LevelSuggestion(
            lead: l10n.driveSuggestedLead,
            level: levelLabel(l10n, s.level),
            reason: l10n.driveYours(s.yours, s.turns),
            yours: s.pips,
            pipsLabel: l10n.a11yDrivePips(s.turns, s.yours, s.turns - s.yours),
          )
        else if (target == null && !setup.noTarget && denied == null)
          Text(
            l10n.driveFinding,
            style: PindoroType.bodyMd.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          ),
        LevelPicker<DriveLevel>(
          steps: levelSteps(l10n, setup.choices),
          selected: setup.chosen,
          suggested: to == DriveTo.run ? null : setup.suggestion?.level,
          suggestedLabel: l10n.driveSuggestedTag,
          semanticsLabel: l10n.a11yDriveHelp,
          onChanged: controller.pickLevel,
        ),
        Text(
          levelNote(l10n, setup.chosen),
          style: PindoroType.bodyMd.copyWith(
            color: PindoroTheme.of(context).colors.textSecondary,
          ),
        ),
        ListGroup(
          children: [
            if (setup.chosen == DriveLevel.off) ...[
              rule(
                PindoroGlyph.locateOff,
                l10n.driveRuleMap,
                l10n.driveRuleMapNote,
              ),
              rule(
                PindoroGlyph.timer,
                l10n.driveRuleTrack,
                l10n.driveRuleTrackNote,
              ),
            ],
            rule(
              PindoroGlyph.info,
              l10n.driveRuleHands,
              l10n.driveRuleHandsNote,
            ),
          ],
        ),
        const DriveWeekCard(),
      ],
    );
  }
}

/// The destination's glyph: Home, Work, the run's car, Surprise me's compass,
/// a place's kind, else a pin.
PindoroGlyph _glyph(DriveTo to, DriveTarget? target) => switch (to) {
  DriveTo.home => PindoroGlyph.home,
  DriveTo.work => PindoroGlyph.briefcase,
  DriveTo.run => PindoroGlyph.car,
  DriveTo.surprise => PindoroGlyph.compass,
  DriveTo.own => switch (target?.place) {
    final p? => landmarkGlyph(p.kind),
    null => PindoroGlyph.pin,
  },
};
