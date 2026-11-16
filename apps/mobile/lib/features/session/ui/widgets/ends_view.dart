import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Both ends (SessionScreen `extent`): a pin on each end of a long street,
/// "End 1" under the first, Confirm once both are down; then the street and
/// how many ends were right.
class EndsView extends ConsumerStatefulWidget {
  const EndsView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onPin,
    required this.onConfirm,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<LatLng> onPin;
  final VoidCallback onConfirm;
  final Future<void> Function() onNext;
  final Widget? chip;

  @override
  ConsumerState<EndsView> createState() => _EndsViewState();
}

class _EndsViewState extends ConsumerState<EndsView> {
  MapProjection? _projection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final c = PindoroTheme.of(context).colors;
    final play = widget.play;
    final task = play.task as ExtentTask;
    final grade = task.grade;
    final pins = task.pins;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return TaskScaffold(
      topBar: widget.topBar,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          pin: pins.firstOrNull,
          morePins: pins.skip(1).toList(),
          truth: grade == null ? null : play.street.geometry,
          onTap: grade == null ? widget.onPin : null,
          onCamera: (p) => setState(() => _projection = p),
          showControls: grade == null,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      overlays: [
        if (pins.length == 1 && grade == null)
          Positioned.fill(
            child: IgnorePointer(
              child: GeoAnchors(
                projection: _projection,
                anchors: [
                  (
                    pins.first,
                    Padding(
                      padding: const EdgeInsets.only(top: PindoroSpace.s8),
                      child: Pill(
                        label: l10n.sessionEndOne,
                        face: c.mapMeasureLabel,
                        lip: c.mapMeasureLine,
                        foreground: c.mapMeasureLabelText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      header: QuestionPlate(
        key: ValueKey((play.index, 'ends')),
        street: play.street,
        settings: settings,
        compact: grade != null,
        prompt: l10n.sessionEndsPrompt,
        glyph: PindoroGlyph.route,
        detail: formatDistance(play.street.lengthM, l10n),
      ),
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: PindoroSpace.s3,
        children: [
          if (pins.length == 1)
            CoachBubble(
              title: l10n.sessionEndsCoachTitle,
              body: l10n.sessionEndsCoachBody,
            ),
          PindoroButton(
            label: l10n.sessionEndsConfirm,
            onPressed: pins.length == 2 ? widget.onConfirm : null,
          ),
        ],
      ),
      result: grade == null
          ? null
          : TaskResult(
              resultKey: play.index,
              tier: grade.tier,
              chip: widget.chip,
              sentence: l10n.sessionEndsResult(grade.hits),
              onNext: widget.onNext,
            ),
    );
  }
}
