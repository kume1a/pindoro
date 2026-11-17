import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets real async work (drift, platform fakes) finish, then settles frames.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the last scrollable on screen (a tab's list, Explore's sheet)
/// until [target] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).last);

/// Taps [target] outside the fake clock so its async handler runs, then
/// settles.
Future<void> tapThrough(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await settle(tester);
}
