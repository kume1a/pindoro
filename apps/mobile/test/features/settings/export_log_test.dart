import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/review_log_export.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;
  late int exports;
  late bool fail;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    exports = 0;
    fail = false;
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 4800)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          reviewLogExportProvider.overrideWithValue(() async {
            exports++;
            if (fail) throw const FileSystemException('disk full');
          }),
        ],
        child: const PindoroApp(initialLocation: Routes.settings),
      ),
    );
    await settle(tester);
  }

  final row = find.text('Export review log (CSV)');

  testWidgets('Settings shares the review log', (tester) async {
    await pump(tester);
    await tapThrough(tester, row);
    expect(exports, 1);
    expect(
      find.text("The review log couldn't be exported. Try again."),
      findsNothing,
    );
  });

  testWidgets('a failed export says so', (tester) async {
    fail = true;
    await pump(tester);
    await tapThrough(tester, row);
    expect(exports, 1);
    expect(
      find.text("The review log couldn't be exported. Try again."),
      findsOneWidget,
    );
  });
}
