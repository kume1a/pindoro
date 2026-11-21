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
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/drive_recording_view.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/street_match_row.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A drive (DriveScreen `setup`, `recording`, `review`; boards V3-50 and
/// V32-10): pick where to and how much help, drive with the voice by level and
/// nothing to tap while moving, and the track is graded once parked. The
/// level screens (V32-20 to V32-41) come with the design system's drive
/// components.
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void leave() => context.canPop() ? context.pop() : context.go(Routes.today);
    return switch (ref.watch(driveControllerProvider)) {
      final DriveSetup s => _Setup(setup: s),
      final DriveRecording r => DriveRecordingView(recording: r),
      final DriveReview r => DriveReviewView(review: r, onDone: leave),
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
                StreetMatchRow(
                  match,
                  check: match == setup.own ? CheckState.on : CheckState.off,
                  onTap: () => controller.pickOwn(match),
                ),
            ],
          ),
        },
        if (denied != null || setup.noTarget)
          ListRow(
            leading: const RowTile(PindoroGlyph.locateOff),
            title: denied != null
                ? l10n.driveNoLocation
                : setup.to == DriveTo.run
                ? l10n.driveNoRun
                : l10n.driveNoTarget,
            onTap: denied == null
                ? null
                : () => unawaited(
                    ref.read(locationServiceProvider).openSettings(denied),
                  ),
          ),
        SectionTitle(l10n.driveLevelTitle),
        if (setup.to == DriveTo.run)
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
        else if (setup.target == null && !setup.noTarget && denied == null)
          Text(
            l10n.driveFinding,
            style: PindoroType.bodyMd.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          ),
        LevelPicker<DriveLevel>(
          steps: levelSteps(l10n, setup.choices),
          selected: setup.chosen,
          suggested: setup.to == DriveTo.run ? null : setup.suggestion?.level,
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

/// A drive's review: the track over the best route, the tier, the numbers
/// and the GPS line; also a past drive's (Past drives).
class DriveReviewView extends ConsumerWidget {
  const DriveReviewView({
    required this.review,
    required this.onDone,
    super.key,
  });

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
      if (review.gaps.count > 0)
        l10n.driveGpsLost(review.gaps.count, formatClock(review.gaps.longest)),
    ].join(' ');
    final lines = match.path.lines;
    final best = graded?.best?.lines ?? const <Polyline>[];
    final points = [
      for (final line in [...lines, ...best]) ...line,
    ];
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final celebration = celebrationFor(tier);
    return Scaffold(
      body: MapLayout(
        map: (insets) => city == null || graph == null || points.isEmpty
            ? const SizedBox.expand()
            : Semantics(
                label: l10n.a11yDriveMap,
                child: mapOf(
                  PindoroMap(
                    area: (bbox: city.bbox, boundary: city.boundary),
                    frame: points,
                    route: (
                      a: points.first,
                      b: graph.at(review.target.junction),
                      drawn: lines,
                      best: best,
                      chip: match.uTurns.isEmpty
                          ? null
                          : (
                              at: match.uTurns.first,
                              label: l10n.driveUTurnHere,
                            ),
                      reached: true,
                    ),
                    names: MapNames.all,
                    topInset: insets.top,
                    bottomInset: insets.bottom,
                  ),
                ),
              ),
        front: [
          if (celebration != null)
            RevealCelebration(revealKey: review, size: celebration),
        ],
        bottom: RevealDock(
          revealKey: review,
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
                            ? l10n.progressNoValue
                            : l10n.driveLongerBy(
                                formatNumber(((stretch - 1) * 100).round()),
                              ),
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
      ),
    );
  }
}
