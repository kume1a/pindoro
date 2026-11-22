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

  testWidgets('a long district wraps to two lines in a narrow column; a short '
      'one keeps to one', (tester) async {
    for (final name in [
      'Nadzaladevi District',
      'Mtatsminda District',
      'Vedzisi, Kazbegi, Gotua, Saburtalo Street',
    ]) {
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 126,
              child: Align(
                alignment: Alignment.topRight,
                child: DistrictChip(name, semanticsLabel: name),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: name);
      expect(find.bySemanticsLabel(name), findsOneWidget);
      final size = tester.getSize(find.byType(DistrictChip));
      expect(size.width, lessThanOrEqualTo(126), reason: name);
      expect(size.height, greaterThan(DistrictChip.height), reason: name);
    }
    await tester.pumpWidget(
      _host(
        const Align(
          alignment: Alignment.topRight,
          child: DistrictChip('Vake District', semanticsLabel: 'Vake District'),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(DistrictChip)).height,
      DistrictChip.height,
    );
  });

  testWidgets('the compass turns against the heading; moved off the car it '
      'is Recentre', (tester) async {
    var recentred = 0;
    Future<void> pump({VoidCallback? onRecentre}) => tester.pumpWidget(
      _host(
        Center(
          child: DriveCompass(
            headingDeg: 90,
            recentreLabel: 'Recentre',
            onRecentre: onRecentre,
          ),
        ),
      ),
    );
    await pump();
    expect(find.bySemanticsLabel('Recentre'), findsNothing);
    final turn = tester.widget<Transform>(
      find.descendant(
        of: find.byType(DriveCompass),
        matching: find.byType(Transform),
      ),
    );
    expect(turn.transform.getRotation().entry(0, 1), closeTo(1, 1e-9));
    await pump(onRecentre: () => recentred++);
    await tester.tap(find.bySemanticsLabel('Recentre'));
    expect(recentred, 1);
  });

  group('goldens', skip: _goldensSkip, () {
    for (final brightness in Brightness.values) {
      testWidgets('drive ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 2000));
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
                      leading: DriveCompass(
                        headingDeg: 30,
                        recentreLabel: 'Recentre',
                      ),
                    ),
                    StoppedControls(
                      semanticsLabel: 'Controls while stopped',
                      muted: false,
                      muteLabel: 'Mute the voice',
                      onMute: () {},
                      level: (
                        icon: PindoroGlyph.map,
                        label: 'Guided',
                        semanticsLabel: 'Level: Guided',
                      ),
                      levelOpen: false,
                      onLevel: () {},
                      routeLabel: 'Route and destination',
                      onRoute: () {},
                    ),
                    DriveBottomBar(
                      semanticsLabel: '3.4 kilometres left',
                      left: '3.4 km',
                      arrival: '12:41',
                      minutes: '9 min',
                      progress: 0.4,
                      leading: DriveCompass(
                        headingDeg: 30,
                        recentreLabel: 'Recentre',
                        onRecentre: () {},
                      ),
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
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        DistrictChip('Vake', semanticsLabel: 'Vake'),
                        SizedBox(
                          width: 140,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: DistrictChip(
                              'Nadzaladevi District',
                              semanticsLabel: 'Nadzaladevi District',
                            ),
                          ),
                        ),
                      ],
                    ),
                    ColoredBox(
                      color: PindoroTheme.of(context).colors.surfaceBase,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          spacing: 8,
                          children: [
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
