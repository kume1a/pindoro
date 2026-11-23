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
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/drive/ui/where_to.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/drive_week_card.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/data/map_style.dart';
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

  /// Back from the settings with location allowed: the same choice again.
  late final AppLifecycleListener _resumed;

  @override
  void dispose() {
    _resumed.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _resumed = AppLifecycleListener(
      onResume: () {
        ref.read(driveControllerProvider.notifier).retry();
        ref.invalidate(preciseLocationProvider);
      },
    );
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
    final state = ref.watch(driveControllerProvider);
    if (_choosing) return const Scaffold();
    return switch (state) {
      final DriveSetup s when s.to == null => _Search(setup: s),
      final DriveSetup s => _Setup(setup: s),
      final DriveRecording r => DriveRecordingView(recording: r),
      final DriveReview r => DebriefScreen(
        id: r.id!,
        onDone: () => leaveDrive(context),
      ),
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

/// A destination chosen (DriveSetup `chosen`, `todaysRun`): where to and how far, the route
/// options, the level picker, Preview (V32-11) and Start in a short sheet; pulled up (or its
/// handle tapped), the suggested level with its reason, what the level does and the week's goal
/// too (SPEC §16.23 item 132).
class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.setup});

  final DriveSetup setup;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  bool _more = false;

  void _show({required bool more}) {
    if (_more != more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
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
        (street: final s?, place: _, junction: _, at: _) => name(s),
        (street: _, place: final p?, junction: _, at: _) => placeLabel(
          p,
          settings,
        ),
        _ => l10n.driveTitle,
      },
    };
    final line = switch ((to, run)) {
      (DriveTo.run, final run?) => runLine(l10n, run, name),
      _ => [
        if (target != null && graph != null)
          const PlaceLine().of(context, ref, targetPoint(graph, target)),
        if (plan != null) ...[
          formatDistance(plan.endM, l10n),
          l10n.driveAboutMin(plan.minutes),
        ],
      ].where((s) => s.isNotEmpty).join(' · '),
    };
    final footer = Row(
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
    );
    final options = setup.options;
    final chosen = setup.suggestion;
    final secondary = PindoroType.bodyMd.copyWith(
      color: PindoroTheme.of(context).colors.textSecondary,
    );
    final content = <Widget>[
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
      if (options.length > 1)
        _RouteOptions(
          options: options,
          chosen: chosen,
          onPick: controller.pickRoute,
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
        )
      // Turns can't be followed from an approximate location (item 131).
      else if (ref.watch(preciseLocationProvider).value == false)
        ListRow(
          leading: const RowTile(PindoroGlyph.locate),
          title: l10n.drivePreciseOff,
          subtitle: l10n.drivePreciseOffNote,
          onTap: () async {
            await ref.read(locationServiceProvider).askPrecise();
            ref.invalidate(preciseLocationProvider);
          },
        ),
      if (target == null &&
          !setup.noTarget &&
          denied == null &&
          to != DriveTo.run)
        Text(l10n.driveFinding, style: secondary),
      LevelPicker<DriveLevel>(
        steps: levelSteps(l10n, setup.choices),
        selected: setup.chosen,
        suggested: to == DriveTo.run ? null : setup.suggestion?.level,
        suggestedLabel: l10n.driveSuggestedTag,
        semanticsLabel: l10n.a11yDriveHelp,
        onChanged: controller.pickLevel,
      ),
      if (_more) ...[
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
          ),
        Text(levelNote(l10n, setup.chosen), style: secondary),
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
    ];
    return Scaffold(
      body: PlanMapLayout(
        semanticsLabel: l10n.a11yRoutesMap,
        route: chosen?.plan.lines ?? const [],
        others: [
          for (final o in options)
            if (o != chosen) ...o.plan.lines,
        ],
        start: setup.here,
        end: target == null || graph == null
            ? null
            : targetPoint(graph, target),
        names: MapNames.everything,
        onTap: options.length < 2
            ? null
            : (at) => controller.pickRoute(_nearest(options, at)),
        top: const PlanMapBack(),
        bottom: BottomPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              // The handle: a tap or a drag up shows the rest, a drag down hides it again.
              Semantics(
                button: true,
                label: _more ? l10n.a11ySetupLess : l10n.a11ySetupMore,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _show(more: !_more),
                  onVerticalDragUpdate: (d) => switch (d.delta.dy) {
                    < 0 => _show(more: true),
                    > 0 => _show(more: false),
                    _ => null,
                  },
                  child: const Center(child: SheetHandle()),
                ),
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : PindoroMotion.durationBase,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: PindoroSpace.s3,
                      children: content,
                    ),
                  ),
                ),
              ),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// The option whose route passes nearest [at].
DriveSuggestion _nearest(List<DriveSuggestion> options, LatLng at) {
  double off(DriveSuggestion s) =>
      pointToPolylineDistance(at, s.plan.lines).distanceMeters;
  return options.reduce((a, b) => off(b) < off(a) ? b : a);
}

/// The route options (SPEC §16.23 items 129, 132) when there is more than one, a line each: the
/// time and length, then Fastest (the quickest) or Most familiar (the most turns you already
/// know), and the side of the road the place is on when the options arrive on both, with the
/// time against the first option for one on the other side; the picked one ticked. A tap picks
/// it; so does a tap on its line on the map.
class _RouteOptions extends StatelessWidget {
  const _RouteOptions({
    required this.options,
    required this.chosen,
    required this.onPick,
  });

  final List<DriveSuggestion> options;
  final DriveSuggestion? chosen;
  final ValueChanged<DriveSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    double known(DriveSuggestion s) => s.turns == 0 ? 0 : s.yours / s.turns;
    int best(bool Function(DriveSuggestion a, DriveSuggestion b) better) =>
        options.indexed.reduce((a, b) => better(b.$2, a.$2) ? b : a).$1;
    final fastest = best((a, b) => a.plan.seconds < b.plan.seconds);
    final familiar = best((a, b) => known(a) > known(b));
    NavSide? side(DriveSuggestion s) => s.plan.stop?.side;
    final first = options.first;
    final sides = options.map(side).toSet().length > 1;
    return ListGroup(
      children: [
        for (final (i, o) in options.indexed)
          () {
            final title = [
              l10n.unitMinutes(o.plan.minutes),
              formatDistance(o.plan.endM, l10n),
            ].join(' · ');
            final minutes = o.plan.minutes - first.plan.minutes;
            // The side first: a short row cuts the end off.
            final tags = [
              if (sides)
                side(o) == NavSide.left
                    ? l10n.driveRouteLeft
                    : l10n.driveRouteRight,
              if (sides && side(o) != side(first) && minutes != 0)
                minutes > 0
                    ? l10n.driveRouteSlower(minutes)
                    : l10n.driveRouteFaster(-minutes),
              if (i == fastest) l10n.driveRouteFastest,
              if (i == familiar && i != fastest) l10n.driveRouteFamiliar,
            ].join(' · ');
            final picked = o == chosen;
            return ListRow(
              dense: true,
              title: title,
              subtitle: tags.isEmpty ? null : tags,
              trailing: picked
                  ? PindoroIcon(PindoroGlyph.checkCircle, color: c.primaryText)
                  : null,
              semanticsLabel: l10n.a11yRouteOption(
                i + 1,
                options.length,
                [
                  title,
                  tags,
                  l10n.driveYours(o.yours, o.turns),
                ].where((s) => s.isNotEmpty).join(', '),
                picked ? 'yes' : 'no',
              ),
              onTap: () => onPick(o),
            );
          }(),
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
    final p? => placeGlyph(p),
    null => PindoroGlyph.pin,
  },
};
