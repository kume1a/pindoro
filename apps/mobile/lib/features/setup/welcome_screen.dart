import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/area_label.dart';
import '../../app/database.dart';
import '../../app/format.dart';
import '../../app/page_scaffold.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../pack/cities.dart';
import '../pack/sqlite_pack_repository.dart';
import '../quiz/setup_states.dart';

/// First run until a round is finished: Pindo, the wordmark in the UI
/// language and the way in (choose a city, or play the saved settings).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final recents = ref.watch(recentCityIdsProvider).value ?? const [];
    final area = settings?.area;
    final difficulty = settings?.lastDifficulty;
    final canResume =
        recents.isNotEmpty &&
        area != null &&
        difficulty != null &&
        pack != null;
    final georgian = Localizations.localeOf(context).languageCode == 'ka';
    final resumes = canResume
        ? [
            georgian ? pack.city().nameKa : pack.city().nameEn,
            areaLabel(context, area, pack, settings),
            difficultyName(l10n, difficulty),
          ].join(' · ')
        : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PindoroSpace.s4,
                PindoroSpace.s2,
                PindoroSpace.s4,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PindoroIconButton(
                    glyph: PindoroGlyph.settings,
                    semanticLabel: l10n.a11ySettings,
                    onPressed: () => context.push(Routes.settings),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PindoroSpace.s4),
                  child: Column(
                    spacing: PindoroSpace.s4,
                    children: [
                      const Pindo(PindoExpression.happy, height: 104),
                      Wordmark(georgian: georgian),
                      Text(
                        l10n.welcomeTagline,
                        textAlign: TextAlign.center,
                        style: PindoroType.bodyLg.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ContentColumn(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  PindoroSpace.s4,
                  0,
                  PindoroSpace.s4,
                  bottomActionGap(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: PindoroSpace.s3,
                  children: [
                    if (resumes == null)
                      LipBox(
                        padding: const EdgeInsets.all(PindoroSpace.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.welcomeEmptyTitle,
                              style: PindoroType.titleMd.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              l10n.welcomeEmptyBody,
                              style: PindoroType.bodySm.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      PindoroButton(
                        label: l10n.welcomeFindCity,
                        icon: PindoroGlyph.search,
                        variant: PindoroButtonVariant.tertiary,
                        onPressed: () => context.push(Routes.city),
                      ),
                      Text(
                        resumes,
                        textAlign: TextAlign.center,
                        style: PindoroType.labelMd.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                    Semantics(
                      label: resumes == null ? null : l10n.a11yPlay(resumes),
                      child: PindoroButton(
                        label: resumes == null
                            ? l10n.commonChooseCity
                            : l10n.commonPlay,
                        icon: resumes == null ? null : PindoroGlyph.play,
                        hero: true,
                        onPressed: () => resumes == null
                            ? context.push(Routes.city)
                            : context.push(Routes.round),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
