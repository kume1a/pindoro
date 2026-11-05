import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/placeholder_screen.dart';
import '../../app/router.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'Results',
    body: 'Round summary: one badge per question, points and xp.',
    actions: [
      PindoroButton(label: 'Home', onPressed: () => context.go(Routes.home)),
    ],
    child: Wrap(
      spacing: PindoroTokens.spaceSm,
      runSpacing: PindoroTokens.spaceSm,
      children: [for (final t in Tier.values) FeedbackBadge(t)],
    ),
  );
}
