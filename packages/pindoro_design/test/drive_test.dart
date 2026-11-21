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
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Mute the voice'));
    await tester.tap(find.text('Quiet'));
    await tester.tap(find.text('End drive'));
    expect(taps, ['mute', 'level', 'end']);
    expect(
      tester.getSize(find.bySemanticsLabel('Mute the voice')).height,
      greaterThanOrEqualTo(PindoroSize.buttonLg),
    );
  });

  testWidgets('a three-figure limit drops to 44 dp to fit the ring', (
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
    expect(size('60'), 54);
    expect(size('110'), 44);
  });

  group('goldens', skip: _goldensSkip, () {
    for (final brightness in Brightness.values) {
      testWidgets('drive ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1780));
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
                    const TurnPlate(
                      semanticsLabel: 'At Vake Park, left onto Chavchavadze',
                      landmark: 'At Vake Park',
                      landmarkKind: DriveGlyphName.park,
                      glyph: DriveGlyphName.left,
                      action: 'Left onto',
                      street: 'Chavchavadze Ave',
                      then: DriveGlyphName.right,
                      thenLabel: 'then',
                      approach: 0.62,
                    ),
                    const DriveBottomBar(
                      semanticsLabel: '3.4 kilometres left',
                      arrival: '12:41',
                      left: '3.4 km',
                      rescued: true,
                      camera: true,
                      sign: SpeedLimitSign(
                        limit: 60,
                        over: true,
                        semanticsLabel: 'Over the speed limit of 60',
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
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: DistrictChip('Vake', semanticsLabel: 'Vake'),
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
