import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';
import '../pack/sqlite_pack_repository.dart';

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
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(packRepositoryProvider).value;
    return PlaceholderScreen(
      title: 'Area',
      body: 'Play the whole city or one district.',
      child: pack == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _AreaTile(
                  const WholeCity(),
                  title: pack.city().nameKa,
                  subtitle: 'whole city',
                ),
                for (final d in pack.districts())
                  _AreaTile(
                    DistrictArea(d.id),
                    title: d.nameKa,
                    subtitle: d.nameEn,
                  ),
              ],
            ),
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile(this.area, {required this.title, this.subtitle});

  final Area area;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    mouseCursor: SystemMouseCursors.click,
    onTap: () async {
      await ref
          .read(databaseProvider)
          .updateSettings(
            UserSettingsCompanion(
              lastAreaJson: Value(jsonEncode(area.toJson())),
            ),
          );
      if (context.mounted) await context.push(Routes.difficulty);
    },
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
