import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildPindoroTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

/// The tops of [text]'s line boxes: one per line it is laid out on.
Set<double> _lineTops(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text))
    .getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    )
    .map((b) => b.top)
    .toSet();

void main() {
  testWidgets('a word wider than its box shrinks instead of breaking; '
      'a sentence still wraps between its words', (tester) async {
    const word = 'ღირსშესანიშნაობის';
    const sentence = 'ღირსშესანიშნაობის დამატება';
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 80,
          child: Column(
            children: [
              WholeWords(Text(word, style: PindoroType.titleMd)),
              WholeWords(Text(sentence, style: PindoroType.titleMd)),
            ],
          ),
        ),
      ),
    );
    expect(_lineTops(tester, word), hasLength(1));
    expect(_lineTops(tester, sentence), hasLength(2));
    for (var i = 0; i < 2; i++) {
      expect(
        tester.getSize(find.byType(WholeWords).at(i)).width,
        lessThanOrEqualTo(80),
      );
    }
  });

  testWidgets('a word that fits is left as it is', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          child: WholeWords(Text('Coached', style: PindoroType.labelLg)),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(WholeWords)).height,
      PindoroType.labelLg.fontSize! * PindoroType.labelLg.height!,
    );
  });

  testWidgets('a button row evens its shares, then stacks, before a label '
      'would break inside a word', (tester) async {
    Future<void> row(String label) => tester.pumpWidget(
      _host(
        SizedBox(
          width: 328,
          child: ButtonRow(
            flex: const [1, 2],
            [
              PindoroButton(
                label: label,
                variant: PindoroButtonVariant.secondary,
                onPressed: () {},
              ),
              PindoroButton(label: 'Go', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    Rect button(String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(PindoroButton)),
    );
    bool stacked(String label) => button('Go').top >= button(label).bottom;
    double width(String text) => button(text).width;
    await row('Map');
    expect(stacked('Map'), isFalse);
    expect(width('Go'), greaterThan(width('Map')));
    await row('წინასწარ ნახვა');
    expect(stacked('წინასწარ ნახვა'), isFalse);
    expect(width('Go'), width('წინასწარ ნახვა'));
    await row('ღირსშესანიშნაობის დამატება');
    expect(stacked('ღირსშესანიშნაობის დამატება'), isTrue);
    expect(width('Go'), 328);
  });
}
