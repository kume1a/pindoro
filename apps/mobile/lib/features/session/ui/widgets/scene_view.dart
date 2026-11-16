import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/pack/data/photo_pack.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/route_view.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A street photo card (RouteItemScreen `sceneAction`, `sceneName`,
/// `sceneResult`; SPEC §3 S1–S3): the photo with its credit, then S1 the
/// street typed, S2 the way to go, or S3 the place on the map and the way
/// it looks. Look around in Google Maps never shares a screen with the map.
class SceneView extends ConsumerStatefulWidget {
  const SceneView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onChoose,
    required this.onPin,
    required this.onAnswer,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<Object> onChoose;
  final ValueChanged<LatLng> onPin;
  final ValueChanged<String> onAnswer;
  final Future<void> Function() onNext;
  final Widget? chip;

  @override
  ConsumerState<SceneView> createState() => _SceneViewState();
}

/// S3's screens: the photo, then the map, then the heading.
enum _Placing { photo, map, heading }

class _SceneViewState extends ConsumerState<SceneView> {
  final _field = TextEditingController();
  var _placing = _Placing.photo;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    if (old.play.index != widget.play.index) {
      _field.clear();
      _placing = _Placing.photo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final play = widget.play;
    final task = play.task as RouteTask;
    final q = task.question as SceneQuestion;
    final image = q.image;
    final tier = task.result;
    final bytes = ref.watch(scenePhotoProvider(image.id)).value;
    String name(NamedStreet? s) => s == null ? '' : streetName(s, settings);
    String compass(double degrees) =>
        l10n.compassWord(compassPointOf(degrees).name);
    final year = image.capturedAt?.year;
    final card = SceneCard(
      photo: bytes == null ? null : MemoryImage(bytes),
      caption: switch (q.n) {
        2 => l10n.sceneApproachCaption(formatDistance(image.distanceM, l10n)),
        1 when year != null => l10n.sceneLookingCaption(
          compass(image.heading),
          '$year',
        ),
        _ when year != null => l10n.sceneTakenCaption('$year'),
        _ => l10n.sceneStreetPhoto,
      },
      attribution: l10n.sceneCredit(
        _sourceName(image.source),
        image.licence,
        image.author,
      ),
      semanticsLabel: l10n.a11yScenePhoto,
      onAttribution: switch (image.link) {
        final link? => () => GoogleMaps.openExternally(Uri.parse(link)),
        null => null,
      },
    );
    final lookAround = PindoroButton(
      label: l10n.sceneLookAround,
      icon: PindoroGlyph.external,
      variant: PindoroButtonVariant.tertiary,
      onPressed: () => GoogleMaps.openExternally(
        GoogleMaps.streetView(image.at, image.heading),
      ),
    );
    Widget result(String sentence, {String? label}) => TaskResult(
      resultKey: play.index,
      tier: tier!,
      label: label,
      chip: widget.chip,
      sentence: sentence,
      chips: [lookAround],
      onNext: widget.onNext,
    );
    Widget scaffold({
      required Widget header,
      Widget? body,
      Widget? map,
      Widget? controls,
      Widget? result,
    }) => TaskScaffold(
      topBar: widget.topBar,
      header: header,
      map: map,
      body: body,
      controls: controls,
      result: result,
    );

    switch (q.n) {
      case 1:
        return scaffold(
          header: AskCard(title: l10n.sceneNameAsk, note: l10n.sceneNameNote),
          body: card,
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              SearchField(
                controller: _field,
                placeholder: l10n.sessionCrossingsHint,
                clearLabel: l10n.commonClear,
                glyph: PindoroGlyph.signpost,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
              PindoroButton(
                label: l10n.commonCheck,
                onPressed: _field.text.trim().isEmpty
                    ? null
                    : () => widget.onAnswer(_field.text),
              ),
              PindoroButton(
                label: l10n.sceneDontKnow,
                variant: PindoroButtonVariant.tertiary,
                onPressed: () => widget.onAnswer(''),
              ),
            ],
          ),
          result: tier == null
              ? null
              : result(
                  l10n.sceneNameResult(
                    otherScript(q.street!, settings) ?? name(q.street),
                    compass(image.heading),
                    formatDistance(image.distanceM, l10n),
                    switch (_crossing(
                      ref.watch(packRepositoryProvider).value?.roadGraph(),
                      q,
                      ref.watch(cityStreetsProvider).value ?? const {},
                    )) {
                      final s? => name(s),
                      null => l10n.sceneTheJunction,
                    },
                  ),
                  label: name(q.street),
                ),
        );

      case 2:
        final right = task.choice == q.correct;
        final word = turnWord(l10n, q.correct!);
        return scaffold(
          header: AskCard(
            title: l10n.sceneTurnAsk,
            note: l10n.sceneHeadingTo(
              _placeName(ref, q.destChunk, settings, l10n),
            ),
          ),
          body: card,
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              Row(
                spacing: PindoroSpace.s2,
                children: [
                  for (final turn in Turn.values)
                    if (q.exits.containsKey(turn))
                      Expanded(
                        child: PindoroButton(
                          label: l10n.sceneExit(turn.name),
                          icon: _turnGlyph(turn),
                          variant: PindoroButtonVariant.secondary,
                          onPressed: () {
                            widget.onChoose(turn);
                            widget.onAnswer('');
                          },
                        ),
                      ),
                ],
              ),
              lookAround,
            ],
          ),
          result: tier == null
              ? null
              : result(
                  right
                      ? l10n.routeTurnRight(word, name(q.exitStreet))
                      : l10n.routeTurnWrong(word, name(q.exitStreet)),
                  label: right ? l10n.routeRight : l10n.routeWrong,
                ),
        );

      default:
        final heading = task.choice as double? ?? 0;
        final placing = tier == null ? _placing : _Placing.heading;
        return switch (placing) {
          _Placing.photo => scaffold(
            header: AskCard(
              title: l10n.scenePlaceAsk,
              note: l10n.scenePlaceNote,
            ),
            body: card,
            controls: PindoroButton(
              label: l10n.scenePlaceStart,
              icon: PindoroGlyph.pinDrop,
              onPressed: () => setState(() => _placing = _Placing.map),
            ),
          ),
          _Placing.map => scaffold(
            header: AskCard(
              title: l10n.scenePlaceAsk,
              note: l10n.scenePlacePin,
            ),
            map: ref.watch(pindoroMapBuilderProvider)(
              PindoroMap(
                area: play.area,
                frame: play.frame,
                pin: play.pin,
                onTap: widget.onPin,
                topInset: MediaQuery.paddingOf(context).top + 180,
                bottomInset: PinDropView.confirmInset(context),
              ),
            ),
            controls: PindoroButton(
              label: l10n.commonNext,
              onPressed: play.pin == null
                  ? null
                  : () => setState(() => _placing = _Placing.heading),
            ),
          ),
          _Placing.heading => scaffold(
            header: AskCard(
              title: l10n.sceneHeadingAsk,
              note: l10n.scenePlaceNote,
            ),
            body: Padding(
              padding: const EdgeInsets.only(top: PindoroSpace.s6),
              child: BearingDial(
                playerBearing: heading,
                trueBearing: tier == null ? null : image.heading,
                enabled: tier == null,
                onChanged: widget.onChoose,
                semanticsLabel: l10n.a11yCompass,
                describeBearing: compass,
                animate: !MediaQuery.disableAnimationsOf(context),
                caption: l10n.sessionBearingCaption(compass(heading)),
              ),
            ),
            controls: PindoroButton(
              label: l10n.commonConfirm,
              onPressed: () => widget.onAnswer(''),
            ),
            result: tier == null
                ? null
                : result(
                    l10n.scenePlaceResult(
                      formatDistance(
                        distanceBetween(play.pin!, image.at),
                        l10n,
                      ),
                      compass(image.heading),
                    ),
                  ),
          ),
        };
    }
  }
}

/// A street the photo's road meets at its junction.
NamedStreet? _crossing(
  RoadGraph? graph,
  SceneQuestion q,
  Map<String, NamedStreet> streets,
) => graph
    ?.edgesAt(q.junction)
    .map((e) => streets[e.streetId])
    .nonNulls
    .where((s) => s != q.street)
    .firstOrNull;

String _sourceName(String source) => switch (source) {
  'mapillary' => 'Mapillary',
  'panoramax' => 'Panoramax',
  _ => source,
};

PindoroGlyph _turnGlyph(Turn turn) => switch (turn) {
  Turn.left => PindoroGlyph.turnLeft,
  Turn.straight => PindoroGlyph.straight,
  Turn.right => PindoroGlyph.turnRight,
  Turn.uTurn => PindoroGlyph.uTurn,
};

String _placeName(
  WidgetRef ref,
  String? chunk,
  Settings? settings,
  AppLocalizations l10n,
) => switch (ref
    .watch(packRepositoryProvider)
    .value
    ?.districts()
    .where((d) => d.id == chunk)
    .firstOrNull) {
  final d? => districtName(d, settings),
  null => l10n.routeCityCentre,
};
