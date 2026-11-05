import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_design/pindoro_design.dart';

import 'router.dart';

class PindoroApp extends StatefulWidget {
  const PindoroApp({super.key, required this.initialLocation});

  final String initialLocation;

  @override
  State<PindoroApp> createState() => _PindoroAppState();
}

class _PindoroAppState extends State<PindoroApp> {
  late final GoRouter _router = buildRouter(widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'პინდორო',
    debugShowCheckedModeBanner: false,
    theme: buildPindoroTheme(Brightness.light),
    darkTheme: buildPindoroTheme(Brightness.dark),
    routerConfig: _router,
  );
}
