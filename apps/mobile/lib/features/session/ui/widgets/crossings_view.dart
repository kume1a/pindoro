import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/street_entry.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The crossings drill (SessionScreen `crossings`): your drive along the
/// street in cobalt from the car, a ring on each crossing, the current one
/// numbered; type each crossing's name (a match row fills it in), Next
/// crossing; answered rings take their tier colour and the street's name.
class CrossingsView extends ConsumerStatefulWidget {
  const CrossingsView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onName,
    required this.onNext,
    required this.onDontKnow,
  });

  final SessionPlaying play;
  final Widget topBar;
  final Future<void> Function(String typed) onName;
  final Future<void> Function() onNext;

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  @override
  ConsumerState<CrossingsView> createState() => _CrossingsViewState();
}

class _CrossingsViewState extends ConsumerState<CrossingsView>
    with MapProjectionHost<CrossingsView> {
  final _field = TextEditingController();
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _field.text.trim();
    if (typed.isEmpty) return;
    _field.clear();
    unawaited(widget.onName(typed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = PindoroTheme.of(context);
    final settings = ref.watch(settingsProvider).value;
    final play = widget.play;
    final task = play.task as CrossingsTask;
    final street = play.street;
    final at = task.named.length;
    final tier = task.result;
    final streets = ref.watch(cityStreetsProvider).value?.values ?? const [];
    final match = tier == null ? suggestStreet(_field.text, streets) : null;
    final heading = compassPoint(task.start, task.crossings.last.at);
    Widget ring(int i) {
      final current = i == at && tier == null;
      final colour = i < at
          ? theme.tier(task.named[i] ? Tier.great : Tier.miss).lip
          : theme.colors.mapPlayerRoute;
      final size = current ? 24.0 : 18.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current) MapTip(formatNumber(i + 1), selected: true),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colour,
                width: current ? PindoroStroke.thick + 1 : PindoroStroke.thick,
              ),
            ),
          ),
        ],
      );
    }

    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return TaskScaffold(
      onDontKnow: widget.onDontKnow,
      topBar: widget.topBar,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          frame: play.frame,
          hit: street.geometry,
          traces: [
            for (final c in task.crossings.take(at)) ...c.street.geometry,
          ],
          names: MapNames(
            streets: {
              street.name,
              for (final c in task.crossings.take(at)) c.street.name,
            },
          ),
          onCamera: onCamera,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      overlays: [
        Positioned.fill(
          child: IgnorePointer(
            child: GeoAnchors(
              projection: projection,
              anchors: [
                for (final (i, c) in task.crossings.indexed) (c.at, ring(i)),
                (
                  task.start,
                  CarMarker(
                    semanticsLabel: l10n.sessionCrossingsFrom(
                      l10n.compassWord(heading.name),
                      streetName(task.from, settings),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      header: QuestionPlate(
        key: ValueKey((play.index, 'crossings')),
        street: street,
        settings: settings,
        compact: tier != null,
        prompt: l10n.sessionCrossingsPrompt,
        glyph: PindoroGlyph.route,
        detail: l10n.sessionCrossingsFrom(
          l10n.compassWord(heading.name),
          streetName(task.from, settings),
        ),
      ),
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          Text(
            l10n.sessionCrossingsCount(
              (at + 1).clamp(1, task.crossings.length),
              task.crossings.length,
            ),
            style: PindoroType.labelMd.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          StreetEntry(
            controller: _field,
            placeholder: l10n.sessionCrossingsHint,
            onChanged: () => setState(() {}),
            onSubmitted: _submit,
            match: match,
            onMatch: () =>
                setState(() => _field.text = streetName(match!, settings)),
          ),
          PindoroButton(
            label: l10n.sessionCrossingsNext,
            onPressed: _field.text.trim().isEmpty ? null : _submit,
          ),
        ],
      ),
      result: tier == null
          ? null
          : TaskResult(
              resultKey: play.index,
              tier: tier,
              sentence: l10n.sessionCrossingsResult(
                task.named.where((n) => n).length,
                task.crossings.length,
              ),
              onNext: widget.onNext,
            ),
    );
  }
}
