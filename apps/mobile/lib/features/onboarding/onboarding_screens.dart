import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/config.dart';
import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PindoroTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroTokens.spaceMd,
          children: [
            const Spacer(),
            const StreetPlate('პინდორო'),
            Text(
              'Learn your city street by street: read the sign, drop a pin '
              'on the unlabelled map.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Spacer(),
            PindoroButton(
              label: 'Start',
              onPressed: () => context.push(Routes.city),
            ),
            if (kDebugMode)
              PindoroButton(
                label: 'Debug map',
                variant: PindoroButtonVariant.ghost,
                onPressed: () => context.push(Routes.quiz),
              ),
          ],
        ),
      ),
    ),
  );
}

class CityScreen extends ConsumerWidget {
  const CityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlaceholderScreen(
    title: 'City',
    body: 'Pick the city you want to learn.',
    actions: [
      PindoroButton(
        label: 'Tbilisi',
        onPressed: () async {
          await ref
              .read(databaseProvider)
              .updateSettings(
                const UserSettingsCompanion(lastCity: Value('tbilisi')),
              );
          if (context.mounted) await context.push(Routes.area);
        },
      ),
    ],
  );
}

class AreaScreen extends ConsumerWidget {
  const AreaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlaceholderScreen(
    title: 'Area',
    body: 'Play the whole city or one district.',
    actions: [
      PindoroButton(
        label: 'Vake',
        onPressed: () async {
          final area = jsonEncode({'district_id': AppConfig.fixtureDistrictId});
          await ref
              .read(databaseProvider)
              .updateSettings(UserSettingsCompanion(lastAreaJson: Value(area)));
          if (context.mounted) await context.push(Routes.difficulty);
        },
      ),
    ],
  );
}

class DifficultyScreen extends ConsumerWidget {
  const DifficultyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlaceholderScreen(
    title: 'Difficulty',
    body: 'Easy asks main roads; expert asks every residential lane.',
    actions: [
      for (final d in Difficulty.values)
        PindoroButton(
          label: d.name,
          variant: PindoroButtonVariant.secondary,
          onPressed: () async {
            await ref
                .read(databaseProvider)
                .updateSettings(
                  UserSettingsCompanion(
                    lastDifficulty: Value(d),
                    onboardingDone: const Value(true),
                  ),
                );
            if (context.mounted) context.go(Routes.home);
          },
        ),
    ],
  );
}
