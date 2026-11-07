import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

const _longName =
    'Ilia Chavchavadze Avenue second dead-end lane with an extraordinarily long name';
const _shortName = 'Vake';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPindoroTheme(brightness),
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

double _fontSizeOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

void main() {
  group('StreetPlate', () {
    testWidgets('short names use the largest size', (tester) async {
      await tester.pumpWidget(_host(const StreetPlate(_shortName)));
      expect(_fontSizeOf(tester, _shortName), PindoroType.headlineMd.fontSize);
    });

    testWidgets('long names shrink but never below the floor or truncate', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(const StreetPlate(_longName)));
      final size = _fontSizeOf(tester, _longName);
      expect(size, lessThan(PindoroType.headlineMd.fontSize!));
      expect(size, greaterThanOrEqualTo(PindoroSize.plateNameMin));
      final text = tester.widget<Text>(find.text(_longName));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    });

    test('plateFontSize steps down in 2 dp steps', () {
      const style = PindoroType.headlineMd;
      final size = plateFontSize(_longName, style, maxWidth: 300);
      final steps = (style.fontSize! - size) / 2;
      expect(steps, steps.roundToDouble());
      expect(plateFontSize('x', style, maxWidth: 300), style.fontSize);
      expect(
        plateFontSize(_longName * 4, style, maxWidth: 100),
        PindoroSize.plateNameMin,
      );
    });
  });

  group('PindoroButton', () {
    testWidgets('taps call onPressed; disabled ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              PindoroButton(label: 'start', onPressed: () => taps++),
              const PindoroButton(label: 'disabled', onPressed: null),
            ],
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.tap(find.text('disabled'));
      expect(taps, 1);
    });

    testWidgets('labels are never uppercased', (tester) async {
      await tester.pumpWidget(
        _host(PindoroButton(label: 'start', onPressed: () {})),
      );
      expect(find.text('start'), findsOneWidget);
      expect(find.text('START'), findsNothing);
    });
  });

  test('celebrations calm down on repeats', () {
    expect(celebrationFor(Tier.perfect), CelebrationSize.big);
    expect(
      celebrationFor(Tier.perfect, perfectsThisRound: 2),
      CelebrationSize.medium,
    );
    expect(celebrationFor(Tier.great, inARow: 4), CelebrationSize.medium);
    expect(celebrationFor(Tier.great, inARow: 5), isNull);
    expect(celebrationFor(Tier.miss), isNull);
  });

  testWidgets('FeedbackBadge shows the tier icon and name', (tester) async {
    await tester.pumpWidget(_host(const FeedbackBadge(Tier.perfect)));
    expect(
      find.byWidgetPredicate(
        (w) => w is PindoroIcon && w.glyph == PindoroGlyph.star,
      ),
      findsOneWidget,
    );
    expect(find.text('perfect'), findsOneWidget);
  });

  group('goldens', skip: _goldensSkip, () {
    Future<void> pumpGallery(WidgetTester tester, Brightness brightness) async {
      await tester.binding.setSurfaceSize(const Size(400, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              const StreetPlate(_shortName),
              const StreetPlate('Grand Union Canal Embankment North'),
              const StreetPlate(_longName),
              PindoroButton(label: 'start', onPressed: () {}),
              PindoroButton(
                label: 'settings',
                variant: PindoroButtonVariant.secondary,
                onPressed: () {},
              ),
              PindoroButton(
                label: 'skip',
                variant: PindoroButtonVariant.tertiary,
                onPressed: () {},
              ),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FeedbackBadge(Tier.perfect),
                  FeedbackBadge(Tier.great),
                  FeedbackBadge(Tier.close),
                  FeedbackBadge(Tier.miss, label: 'missed by 1.2 km'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('light', (tester) async {
      await pumpGallery(tester, Brightness.light);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/gallery_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpGallery(tester, Brightness.dark);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/gallery_dark.png'),
      );
    });
  });
}

// Glyph rasterisation differs per OS, so goldens are rendered and compared on
// Linux only (CI, and `just goldens` regenerates them in a Linux container).
final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
