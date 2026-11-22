import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/drive/ui/drive_cards.dart';
import 'package:pindoro/features/drive/ui/where_to.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/progress.dart';

/// The Drive tab, first in the bar and the page the app opens on (SPEC §16.23 item 129): Where
/// to, then the drives. A pick opens the drive on it; back here, and on every return to the app,
/// where the phone is and the minutes to Home and Work are found again.
class DriveTab extends ConsumerStatefulWidget {
  const DriveTab({super.key});

  @override
  ConsumerState<DriveTab> createState() => _DriveTabState();
}

class _DriveTabState extends ConsumerState<DriveTab> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() => ref
    ..invalidate(driveHereProvider)
    ..invalidate(recentDestinationsProvider);

  Future<void> _open(String route, {Object? extra}) async {
    await context.push(route, extra: extra);
    _refresh();
    refreshLearning(ref);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: context.l10n.driveTitle,
    showBack: false,
    children: [
      WhereTo(
        onChoose: (to) => unawaited(_open(Routes.driveTo(to.name))),
        onPick: (dest) => unawaited(_open(Routes.drive, extra: dest)),
        below: [DriveCards(onOpen: _open)],
      ),
    ],
  );
}
