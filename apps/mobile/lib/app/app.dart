import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../l10n/app_localizations.dart';
import 'launch_overlay.dart';
import 'router.dart';
import 'settings.dart';

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

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    return MaterialApp.router(
      title: 'პინდორო',
      debugShowCheckedModeBanner: false,
      theme: buildPindoroTheme(Brightness.light),
      darkTheme: buildPindoroTheme(Brightness.dark),
      themeMode: settings?.themeMode ?? ThemeMode.system,
      themeAnimationDuration: PindoroMotion.durationBase,
      locale: settings?.locale,
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
