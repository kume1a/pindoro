import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/launch_overlay.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/pack/data/app_update.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:url_launcher/url_launcher.dart';

final _lightTheme = buildPindoroTheme(Brightness.light);
final _darkTheme = buildPindoroTheme(Brightness.dark);

class PindoroApp extends ConsumerStatefulWidget {
  const PindoroApp({
    super.key,
    required this.initialLocation,
    this.coldStart = false,
  });

  final String initialLocation;

  /// Plays the launch moment over the first page.
  final bool coldStart;

  @override
  ConsumerState<PindoroApp> createState() => _PindoroAppState();
}

class _PindoroAppState extends ConsumerState<PindoroApp> {
  late final GoRouter _router = buildRouter(widget.initialLocation);

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The date may have changed while the app was away, and so may the XP.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref
        ..invalidate(streakProvider)
        ..invalidate(standingProvider),
    );
    // Listening keeps the standing alive, so the week's XP reaches the
    // league at launch, on resume and after a lesson, not only on its tab.
    ref.listenManual(standingProvider, (_, _) {});
    // Keeps the one reminder in step with the streak and the settings;
    // switching it off in Settings cancels it there.
    ref.listenManual(reminderProvider, (_, next) {
      if (next case AsyncData(value: final notice?)) {
        unawaited(ref.read(remindersProvider).schedule(notice));
      }
    }, fireImmediately: true);
    ref.listenManual(appUpdateProvider, (_, next) {
      if (next case AsyncData(value: final url?)) unawaited(_offerUpdate(url));
    });
  }

  /// Once per launch: a newer build is out, download it?
  Future<void> _offerUpdate(Uri url) async {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    final l10n = context.l10n;
    final later = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.updateTitle,
        body: l10n.updateBody,
        primary: l10n.updateDownload,
        secondary: l10n.updateLater,
      ),
    );
    if (later == false) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only theme and language rebuild the app; other settings writes don't.
    final (themeMode, locale) = ref.watch(
      settingsProvider.select(
        (s) => (s.value?.themeMode ?? ThemeMode.system, s.value?.locale),
      ),
    );
    return MaterialApp.router(
      title: 'Pindoro',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: PindoroMotion.durationBase,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      builder: widget.coldStart
          ? (context, child) => LaunchOverlay(child: child!)
          : null,
    );
  }
}
