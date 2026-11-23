import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPindoroTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

enum _Level { guided, coached, quiet, off }

List<LevelStep<_Level>> _steps({Set<_Level> disabled = const {}}) => [
  for (final (l, icon) in [
    (_Level.guided, PindoroGlyph.map),
    (_Level.coached, PindoroGlyph.soundOn),
    (_Level.quiet, PindoroGlyph.compass),
    (_Level.off, PindoroGlyph.locateOff),
  ])
    (
      value: l,
      label: l.name,
      icon: icon,
      disabledReason: disabled.contains(l)
          ? 'Two steps past the suggestion'
          : null,
    ),
];

const List<RouteCard> _cards = [
  (tag: 'Now', time: '16 min', length: '15.8 km', note: null),
  (tag: '+3 min', time: '19 min', length: '14.2 km', note: 'On your left'),
];

void main() {
  testWidgets('the level picker applies a tap at once; a disabled step '
      'says why and changes nothing', (tester) async {
    final picked = <_Level>[];
    await tester.pumpWidget(
      _host(
        LevelPicker<_Level>(
          steps: _steps(disabled: {_Level.off}),
          selected: _Level.guided,
          suggested: _Level.guided,
          suggestedLabel: 'Suggested',
          onChanged: picked.add,
          semanticsLabel: 'How much help on this drive',
        ),
      ),
    );
    expect(find.text('Suggested'), findsOneWidget);
    await tester.tap(find.text('quiet'));
    await tester.tap(find.text('off'));
    await tester.tap(find.text('guided'));
    expect(picked, [_Level.quiet]);
    await tester.longPress(find.text('off'));
    await tester.pumpAndSettle();
    expect(find.text('Two steps past the suggestion'), findsOneWidget);
  });

  testWidgets('the stopped bar mutes, opens the level and ends the drive', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.bottomCenter,
          child: StoppedBar(
            semanticsLabel: 'Controls while stopped',
            left: '3.4 km left',
            arrival: 'Arrive 12:41',
            muted: false,
            muteLabel: 'Mute the voice',
            onMute: () => taps.add('mute'),
            level: (
              icon: PindoroGlyph.compass,
              label: 'Quiet',
              semanticsLabel: 'Level: Quiet. Change.',
            ),
            levelOpen: false,
            onLevel: () => taps.add('level'),
            endLabel: 'End drive',
            onEnd: () => taps.add('end'),
            routeLabel: 'Route and destination',
            onRoute: () => taps.add('route'),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Mute the voice'));
    await tester.tap(find.text('Quiet'));
    await tester.tap(find.bySemanticsLabel('Route and destination'));
    await tester.tap(find.text('End drive'));
    expect(taps, ['mute', 'level', 'route', 'end']);
    expect(
      tester.getSize(find.bySemanticsLabel('Mute the voice')).height,
      greaterThanOrEqualTo(PindoroSize.buttonLg),
    );
  });

  testWidgets('a three-figure limit drops to 26 dp to fit the ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Row(
          children: [
            SpeedLimitSign(limit: 60, semanticsLabel: 'Speed limit 60'),
            SpeedLimitSign(limit: 110, semanticsLabel: 'Speed limit 110'),
          ],
        ),
      ),
    );
    double size(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;
    expect(size('60'), 32);
    expect(size('110'), 26);
  });

  testWidgets('a long street keeps to one line, cut short in the room it has', (
    tester,
  ) async {
    const name = 'Vedzisi, Kazbegi, Gotua, Saburtalo Street';
    await tester.pumpWidget(
      _host(
        const Center(
          child: SizedBox(
            width: 200,
            child: Center(child: StreetChip(name, semanticsLabel: 'On $name')),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('On $name'), findsOneWidget);
    final size = tester.getSize(find.byType(StreetChip));
    expect(size.width, lessThanOrEqualTo(200));
    expect(size.height, StreetChip.height);
  });

  testWidgets('the compass turns against the map\'s bearing and switches on a '
      'tap; Recentre takes a tap', (tester) async {
    var taps = 0;
    var recentred = 0;
    await tester.pumpWidget(
      _host(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DriveCompass(
                bearingDeg: 90,
                label: 'North up',
                onTap: () => taps++,
              ),
              DriveRecentre(label: 'Recentre', onTap: () => recentred++),
            ],
          ),
        ),
      ),
    );
    final turn = tester.widget<Transform>(
      find.descendant(
        of: find.byType(DriveCompass),
        matching: find.byType(Transform),
      ),
    );
    expect(turn.transform.getRotation().entry(0, 1), closeTo(1, 1e-9));
    await tester.tap(find.bySemanticsLabel('North up'));
    await tester.tap(find.bySemanticsLabel('Recentre'));
    expect((taps, recentred), (1, 1));
  });

  testWidgets('the routes: a card picks its way, the button takes it; the '
      'ends: To changes it, a stop goes, Add stop', (tester) async {
    final picked = <int>[];
    final removed = <int>[];
    var taken = 0, to = 0, added = 0;
    await tester.pumpWidget(
      _host(
        RouteOptions(
          semanticsLabel: 'Routes',
          ends: RouteEnds(
            fromLabel: 'From',
            from: 'Current location',
            toLabel: 'To',
            to: 'Tbilisi Mall',
            stops: const [
              (label: 'Stop 1', name: 'Nikora', removeLabel: 'Remove Nikora'),
            ],
            onRemove: removed.add,
            onTo: () => to++,
            addLabel: 'Add stop',
            onAdd: () => added++,
          ),
          cards: _cards,
          onPick: picked.add,
          selected: 1,
          takeLabel: 'Take this route',
          onTake: () => taken++,
        ),
      ),
    );
    await tester.tap(find.text('+3 min'));
    await tester.tap(find.text('Take this route'));
    await tester.tap(find.bySemanticsLabel('To Tbilisi Mall'));
    await tester.tap(find.bySemanticsLabel('Remove Nikora'));
    await tester.tap(find.text('Add stop'));
    expect(picked, [1]);
    expect(removed, [0]);
    expect((taken, to, added), (1, 1, 1));
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('+3 min, 19 min, 14.2 km, On your left'),
      ),
      isSemantics(isSelected: true),
    );
  });

  group('goldens', skip: _goldensSkip, () {
    for (final brightness in Brightness.values) {
      testWidgets('drive ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 2700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Builder(
              builder: (context) => ColoredBox(
                color: PindoroTheme.of(context).colors.driveQuietBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    const Align(
                      alignment: Alignment.topLeft,
                      child: TurnPlate(
                        semanticsLabel:
                            'In 300 m, at Vake Park, left onto Chavchavadze',
                        glyph: DriveGlyphName.left,
                        headline: '300 m',
                        street: 'Chavchavadze Ave',
                        note: 'At Vake Park',
                        noteKind: DriveGlyphName.park,
                        lanes: [
                          (arrowsDeg: [-90], use: -90),
                          (arrowsDeg: [-90, 0], use: -90),
                          (arrowsDeg: [0], use: null),
                          (arrowsDeg: [0, 90], use: null),
                          (arrowsDeg: [90], use: null),
                          (arrowsDeg: [180], use: null),
                        ],
                        then: DriveGlyphName.right,
                        thenLabel: 'then',
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        CameraBadge(),
                        SpeedNow(kmh: 72, semanticsLabel: 'Your speed 72'),
                        SpeedLimitSign(
                          limit: 60,
                          over: true,
                          semanticsLabel: 'Over the speed limit of 60',
                        ),
                      ],
                    ),
                    const DriveBottomBar(
                      semanticsLabel: '3.4 kilometres left',
                      left: '3.4 km',
                      arrival: '12:41',
                      minutes: '9 min',
                      progress: 0.4,
                      rescued: true,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        const StreetChip(
                          'Chavchavadze Ave',
                          semanticsLabel: 'On Chavchavadze Ave',
                        ),
                        DriveMapButton(
                          label: 'Routes',
                          onTap: () {},
                          child: DriveGlyph(
                            DriveGlyphName.routes,
                            size: 28,
                            color: PindoroTheme.of(context).colors.driveText,
                            cut: PindoroTheme.of(context).colors.driveSurface,
                          ),
                        ),
                        DriveMapButton(
                          label: 'Mute the voice',
                          onTap: () {},
                          child: DriveMapButton.glyph(
                            context,
                            PindoroGlyph.soundOn,
                          ),
                        ),
                        DriveCompass(
                          bearingDeg: 30,
                          label: 'North up',
                          onTap: () {},
                        ),
                        DriveRecentre(label: 'Recentre', onTap: () {}),
                      ],
                    ),
                    LevelPickerCard(
                      title: 'Level for the rest of this drive',
                      reason: '14 of 17',
                      picker: LevelPicker<_Level>(
                        steps: _steps(),
                        selected: _Level.guided,
                        suggested: _Level.coached,
                        suggestedLabel: 'Suggested',
                        onChanged: (_) {},
                        semanticsLabel: 'Level',
                      ),
                    ),
                    RouteOptions(
                      semanticsLabel: 'Routes',
                      ends: const RouteEnds(
                        fromLabel: 'From',
                        from: 'Current location',
                        toLabel: 'To',
                        to: 'Tbilisi Mall',
                        stops: [
                          (
                            label: 'Stop 1',
                            name: 'Nikora',
                            removeLabel: 'Remove Nikora',
                          ),
                        ],
                        addLabel: 'Add stop',
                      ),
                      cards: _cards,
                      onPick: (_) {},
                      selected: 1,
                      takeLabel: 'Take this route',
                      onTake: () {},
                    ),
                    const Row(
                      spacing: 8,
                      children: [
                        RouteCallout(['16 min', '15.8 km'], picked: true),
                        RouteCallout(['+3 min']),
                      ],
                    ),
                    DriveBottomBar(
                      semanticsLabel: '3.4 kilometres left',
                      left: '3.4 km',
                      arrival: '12:41',
                      minutes: '9 min',
                      progress: 0.4,
                      trailing: DriveBarButton(
                        glyph: PindoroGlyph.close,
                        label: 'End drive',
                        onTap: () {},
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in DriveGlyphName.values)
                          DriveGlyph(
                            g,
                            size: 44,
                            color: PindoroTheme.of(
                              context,
                            ).colors.drivePlateGlyph,
                            cut: PindoroTheme.of(context).colors.driveQuietBg,
                          ),
                      ],
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        StatusDot(
                          status: DriveStatus.good,
                          semanticsLabel: 'On a good path',
                          ring: 0.79,
                        ),
                        StatusDot(
                          status: DriveStatus.recovering,
                          semanticsLabel: 'Recovering',
                        ),
                        StatusDot(
                          status: DriveStatus.lost,
                          semanticsLabel: 'Finding your position',
                        ),
                        SpeedLimitSign(
                          limit: 110,
                          semanticsLabel: 'Speed limit 110',
                        ),
                        RecordingDot(semanticsLabel: 'Recording your drive'),
                      ],
                    ),
                    const Center(
                      child: HeadingDial(
                        heading: 315,
                        letter: 'NW',
                        status: DriveStatus.good,
                        semanticsLabel: 'Heading north-west',
                      ),
                    ),
                    const DistrictLine('Nadzaladevi'),
                    const RecoveryBand(),
                    ColoredBox(
                      color: PindoroTheme.of(context).colors.surfaceBase,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          spacing: 8,
                          children: [
                            ListGroup(
                              children: [
                                ListRow(
                                  dense: true,
                                  title: '12 min · 3.2 km',
                                  subtitle: 'Fastest · On your right',
                                  trailing: PindoroIcon(
                                    PindoroGlyph.checkCircle,
                                    color: PindoroTheme.of(
                                      context,
                                    ).colors.primaryText,
                                  ),
                                  onTap: () {},
                                ),
                                ListRow(
                                  dense: true,
                                  title: '10 min · 2.9 km',
                                  subtitle: '−2 min · On your left',
                                  onTap: () {},
                                ),
                              ],
                            ),
                            LevelSuggestion(
                              lead: 'Suggested:',
                              level: 'Quiet',
                              reason: '14 of 17 turns are yours',
                              yours: [for (var i = 0; i < 17; i++) i % 6 != 3],
                            ),
                            LevelPicker<_Level>(
                              steps: _steps(disabled: {_Level.off}),
                              selected: _Level.quiet,
                              suggested: _Level.coached,
                              suggestedLabel: 'Suggested',
                              onChanged: (_) {},
                              semanticsLabel: 'Level',
                            ),
                          ],
                        ),
                      ),
                    ),
                    StoppedBar(
                      semanticsLabel: 'Controls while stopped',
                      left: '3.4 km left',
                      arrival: 'Arrive 12:41',
                      muted: true,
                      muteLabel: 'Unmute the voice',
                      onMute: () {},
                      level: (
                        icon: PindoroGlyph.compass,
                        label: 'Quiet',
                        semanticsLabel: 'Level: Quiet',
                      ),
                      levelOpen: true,
                      onLevel: () {},
                      endLabel: 'End drive',
                      onEnd: () {},
                      routeLabel: 'Route and destination',
                      onRoute: () {},
                      pickerTitle: 'Level for the rest of this drive',
                      pickerReason: '14 of 17',
                      picker: LevelPicker<_Level>(
                        steps: _steps(),
                        selected: _Level.quiet,
                        suggested: _Level.quiet,
                        suggestedLabel: 'Suggested',
                        onChanged: (_) {},
                        semanticsLabel: 'Level',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/drive_${brightness.name}.png'),
        );
      });
    }
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
