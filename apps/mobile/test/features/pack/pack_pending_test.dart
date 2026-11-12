import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

class _Errors extends GameFeedback {
  _Errors() : super(sounds: Sounds(), haptics: false, sound: false);

  int count = 0;

  @override
  void error() => count++;
}

void main() {
  late _Errors errors;
  late List<Completer<PackRepository>> loads;

  Future<void> pump(WidgetTester tester) async {
    errors = _Errors();
    loads = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedbackProvider.overrideWithValue(errors),
          packRepositoryProvider.overrideWith((ref) {
            loads.add(Completer());
            return loads.last.future;
          }),
        ],
        child: MaterialApp.router(
          theme: buildPindoroTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Consumer(
                  builder: (_, ref, _) =>
                      PackPending(pack: ref.watch(packRepositoryProvider)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a failure buzzes once it settles, not when Try again starts', (
    tester,
  ) async {
    await pump(tester);
    loads.last.completeError(const PackUnavailable('batumi'));
    await tester.pumpAndSettle();
    expect(errors.count, 1);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(loads, hasLength(2));
    expect(errors.count, 1, reason: 'the retry has not failed yet');

    loads.last.completeError(const PackUnavailable('batumi'));
    await tester.pumpAndSettle();
    expect(errors.count, 2);
  });

  testWidgets('a pack only a newer app reads asks for an update', (
    tester,
  ) async {
    await pump(tester);
    loads.last.completeError(
      const PackUnavailable('batumi', needsUpdate: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('This city needs a newer Pindoro'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
