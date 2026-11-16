import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A GPS-free drive (DriveScreen `setup`, `recording`, `review`, board
/// V3-50): no map and nothing to tap while moving; the track is graded
/// once parked.
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void leave() => context.canPop() ? context.pop() : context.go(Routes.today);
    return switch (ref.watch(driveControllerProvider)) {
      final DriveSetup s => _Setup(setup: s),
      final DriveRecording r => _Recording(recording: r),
      final DriveReview r => _Review(review: r, onDone: leave),
    };
  }
}

class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.setup});

  final DriveSetup setup;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final controller = ref.read(driveControllerProvider.notifier);
    final setup = widget.setup;
    final run = ref.watch(todayRunProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final match = setup.to == DriveTo.own
        ? suggestStreet(_field.text, streets.values.toSet())
        : null;
    String name(NamedStreet s) => streetName(s, settings);
    final ready = switch (setup.to) {
      DriveTo.run => run != null,
      DriveTo.surprise => true,
      DriveTo.own => setup.own != null,
    };
    Widget rule(PindoroGlyph glyph, String title, String note) =>
        ListRow(leading: RowTile(glyph), title: title, subtitle: note);
    final denied = setup.denied;
    return PageScaffold(
      title: l10n.driveTitle,
      footer: PindoroButton(
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
      children: [
        SegmentedControl<DriveTo>(
          segments: {
            DriveTo.run: l10n.driveTodaysRun,
            DriveTo.surprise: l10n.driveSurprise,
            DriveTo.own: l10n.driveMyOwn,
          },
          selected: setup.to,
          onChanged: controller.choose,
        ),
        switch (setup.to) {
          DriveTo.run => ListGroup(
            children: [
              ListRow(
                leading: const RowTile(PindoroGlyph.route),
                title: l10n.driveTodaysRun,
                subtitle: run == null
                    ? l10n.driveNoRun
                    : _runLine(l10n, run, name),
              ),
            ],
          ),
          DriveTo.surprise => ListGroup(
            children: [
              ListRow(
                leading: const RowTile(PindoroGlyph.gift),
                title: l10n.driveSurprise,
                subtitle: l10n.driveSurpriseNote,
              ),
            ],
          ),
          DriveTo.own => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              SearchField(
                controller: _field,
                placeholder: l10n.driveWhereTo,
                clearLabel: l10n.commonClear,
                glyph: PindoroGlyph.signpost,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              if (match != null)
                ListRow(
                  leading: const RowTile(PindoroGlyph.signpost),
                  title: name(match),
                  subtitle: otherScript(match, settings),
                  check: match == setup.own ? CheckState.on : CheckState.off,
                  onTap: () => controller.pickOwn(match),
                ),
            ],
          ),
        },
        if (denied != null || setup.noTarget)
          ListRow(
            leading: const RowTile(PindoroGlyph.locateOff),
            title: denied != null ? l10n.driveNoLocation : l10n.driveNoRun,
            onTap: denied == null
                ? null
                : () => unawaited(
                    ref.read(locationServiceProvider).openSettings(denied),
                  ),
          ),
        ListGroup(
          children: [
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
            rule(
              PindoroGlyph.info,
              l10n.driveRuleHands,
              l10n.driveRuleHandsNote,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Paliashvili St → Tamarashvili St · 2.4 km".
String _runLine(
  AppLocalizations l10n,
  RunToDrive run,
  String Function(NamedStreet) name,
) => l10n.todayRunRoute(
  name(run.ends.fromStreet),
  name(run.ends.toStreet),
  formatDistance(run.ends.best.lengthM, l10n),
);

class _Recording extends ConsumerStatefulWidget {
  const _Recording({required this.recording});

  final DriveRecording recording;

  @override
  ConsumerState<_Recording> createState() => _RecordingState();
}

class _RecordingState extends ConsumerState<_Recording> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _showTheWay() async {
    final graph = ref.read(drivingGraphProvider).value;
    final at = graph?.at(widget.recording.target.junction);
    await ref.read(driveControllerProvider.notifier).abandon();
    if (at == null) return;
    await GoogleMaps.openExternally(GoogleMaps.directions(at));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final settings = ref.watch(settingsProvider).value;
    final recording = widget.recording;
    final elapsed = ref.read(clockProvider)().difference(recording.startedAt);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final target = recording.target.street;
    return PageScaffold(
      showBack: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          PindoroButton(
            label: l10n.driveEnd,
            icon: PindoroGlyph.stop,
            onPressed: () =>
                unawaited(ref.read(driveControllerProvider.notifier).end()),
          ),
          PindoroButton(
            label: l10n.driveLost,
            variant: PindoroButtonVariant.tertiary,
            onPressed: () => unawaited(_showTheWay()),
          ),
        ],
      ),
      children: [
        const SizedBox(height: PindoroSpace.s8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: PindoroSpace.s2,
          children: [
            Container(
              width: PindoroSpace.s3,
              height: PindoroSpace.s3,
              decoration: BoxDecoration(
                color: theme.tier(Tier.miss).lip,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              l10n.driveRecording,
              style: PindoroType.labelLg.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        Semantics(
          liveRegion: false,
          child: Text(
            '$minutes:$seconds',
            textAlign: TextAlign.center,
            style: PindoroType.numericXl.copyWith(color: c.textPrimary),
          ),
        ),
        Text(
          l10n.driveSoFar(formatDistance(recording.drivenM, l10n)),
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: PindoroSpace.s4),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.flag),
              title: l10n.driveHeadingTo(streetName(target, settings)),
              subtitle: otherScript(target, settings),
            ),
          ],
        ),
      ],
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review({required this.review, required this.onDone});

  final DriveReview review;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final city = ref.watch(packRepositoryProvider).value?.city();
    final graded = review.graded;
    final match = review.match;
    final tier = graded?.tier ?? Tier.miss;
    final uTurns = match.uTurns.length;
    final stretch = graded?.stretch;
    final target = streetName(review.target.street, settings);
    final sentence = [
      if (graded == null)
        l10n.driveNoTrack
      else if (review.stoppedM case final m?)
        l10n.driveStoppedShort(formatDistance(m, l10n), target)
      else if (tier == Tier.miss)
        l10n.driveLongWay
      else
        l10n.driveFound,
      if (uTurns > 0) l10n.driveUTurns(uTurns),
      if (match.hesitations.isNotEmpty)
        l10n.driveHesitations(match.hesitations.length),
      if (graded != null)
        l10n.driveCredited(
          formatNumber(review.credited),
          formatNumber(review.failed),
        ),
    ].join(' ');
    final lines = match.path.lines;
    final best = graded?.best?.lines ?? const <Polyline>[];
    final points = [
      for (final line in [...lines, ...best]) ...line,
    ];
    return Scaffold(
      body: Stack(
        children: [
          if (city != null && graph != null && points.isNotEmpty)
            Semantics(
              label: l10n.a11yDriveMap,
              child: ref.watch(pindoroMapBuilderProvider)(
                PindoroMap(
                  area: (bbox: city.bbox, boundary: city.boundary),
                  frame: points,
                  route: (
                    a: points.first,
                    b: graph.at(review.target.junction),
                    street: const [],
                    drawn: lines,
                    best: best,
                    ghost: const [],
                    car: null,
                    chip: match.uTurns.isEmpty
                        ? null
                        : (
                            at: match.uTurns.first,
                            label: l10n.driveUTurnHere,
                            anchor: 'bottom',
                          ),
                    reached: true,
                  ),
                  topInset: MediaQuery.paddingOf(context).top,
                  bottomInset: 420,
                ),
              ),
            ),
          RevealDock(
            revealKey: review,
            celebration: celebrationFor(tier),
            sheet: TierRevealSheet(
              tier: tier,
              label: tierLabel(l10n, tier),
              sentence: sentence,
              chips: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    spacing: PindoroSpace.s2,
                    children: [
                      Expanded(
                        child: StatTile(
                          label: l10n.driveDriven,
                          value: formatDistance(match.drivenM, l10n),
                          glyph: PindoroGlyph.car,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: l10n.driveLonger,
                          value: stretch == null
                              ? '–'
                              : '+${formatNumber(((stretch - 1) * 100).round())} %',
                          glyph: PindoroGlyph.route,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: l10n.driveUTurnsTile,
                          value: formatNumber(uTurns),
                          glyph: PindoroGlyph.uTurn,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              action: l10n.commonDone,
              onNext: () async => onDone(),
            ),
          ),
        ],
      ),
    );
  }
}
