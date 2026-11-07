import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/ui/daily_goal.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:url_launcher/url_launcher.dart';

/// Language, street names, theme, sound, haptics; changes apply at once.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const Scaffold();
    final dao = ref.read(settingsDaoProvider);
    final feedback = ref.read(feedbackProvider);
    void save(Future<void> Function() write) {
      feedback.tap();
      write();
    }

    final language =
        settings.appLanguage ??
        (context.georgian ? AppLanguage.ka : AppLanguage.en);
    return PageScaffold(
      title: l10n.settingsTitle,
      children: [
        SectionTitle(l10n.settingsLanguage),
        _Labelled(
          label: l10n.settingsAppLanguage,
          child: SegmentedControl(
            segments: const {
              AppLanguage.en: 'English',
              AppLanguage.ka: 'ქართული',
            },
            selected: language,
            onChanged: (v) => save(() => dao.setLanguage(v)),
          ),
        ),
        _Labelled(
          label: l10n.settingsStreetNames,
          help: l10n.settingsStreetNamesHelp,
          child: SegmentedControl(
            segments: {
              StreetNameMode.local: l10n.settingsStreetNamesLocal,
              StreetNameMode.english: l10n.settingsStreetNamesEnglish,
            },
            selected: settings.streetNames,
            onChanged: (v) => save(() => dao.setStreetNames(v)),
          ),
        ),
        SectionTitle(l10n.settingsDailyGoal),
        ListGroup(
          children: [
            ListRow(
              title: l10n.dailyGoalPerDay(formatNumber(settings.dailyGoal)),
              subtitle: l10n.dailyGoalKeepsStreak(
                goalRounds(context, settings.dailyGoal),
              ),
              leading: const RowTile(PindoroGlyph.flame),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => showDailyGoalSheet(context, ref),
            ),
          ],
        ),
        SectionTitle(l10n.settingsDisplay),
        _Labelled(
          label: l10n.settingsTheme,
          child: SegmentedControl(
            segments: {
              ThemePreference.light: l10n.settingsThemeLight,
              ThemePreference.dark: l10n.settingsThemeDark,
              ThemePreference.system: l10n.settingsThemeSystem,
            },
            selected: settings.theme,
            onChanged: (v) => save(() => dao.setTheme(v)),
          ),
        ),
        ListGroup(
          children: [
            _ToggleRow(
              title: l10n.settingsSound,
              subtitle: l10n.settingsSoundSubtitle,
              glyph: settings.sound
                  ? PindoroGlyph.soundOn
                  : PindoroGlyph.soundOff,
              value: settings.sound,
              onChanged: (v) => save(() => dao.setSound(on: v)),
            ),
            _ToggleRow(
              title: l10n.settingsHaptics,
              subtitle: l10n.settingsHapticsSubtitle,
              glyph: PindoroGlyph.haptics,
              value: settings.haptics,
              // Turning haptics on buzzes once to show them; feedback still
              // has them off until the setting saves.
              onChanged: (v) {
                if (v) unawaited(HapticFeedback.selectionClick());
                unawaited(dao.setHaptics(on: v));
              },
            ),
          ],
        ),
        SectionTitle(l10n.settingsAbout),
        ListGroup(
          children: [
            ListRow(
              title: l10n.creditsTitle,
              leading: const RowTile(PindoroGlyph.map),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.credits),
            ),
          ],
        ),
      ],
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child, this.help});

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s2,
      children: [
        Text(label, style: PindoroType.labelLg.copyWith(color: c.textPrimary)),
        child,
        if (help != null)
          Text(
            help!,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.glyph,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final PindoroGlyph glyph;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ListRow(
    title: title,
    subtitle: subtitle,
    leading: RowTile(glyph),
    trailing: ExcludeSemantics(
      child: PindoroToggle(value: value, onChanged: onChanged),
    ),
    toggled: value,
    onTap: () => onChanged(!value),
  );
}

/// Map data credits: OpenStreetMap (ODbL), Protomaps tiles, FiraGO (OFL) and
/// every package licence.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static final Uri _osmCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final body = PindoroType.bodyMd.copyWith(color: c.textSecondary);
    return PageScaffold(
      title: l10n.creditsTitle,
      children: [
        Text(l10n.creditsIntro, style: body),
        ListGroup(
          children: [
            ListRow(
              title: l10n.creditsOsm,
              subtitle: l10n.creditsOsmLicence,
              leading: const RowTile(PindoroGlyph.map),
              trailing: const PindoroIcon(PindoroGlyph.share),
              semanticsLabel: '${l10n.creditsOsm}. ${l10n.creditsOsmLink}',
              onTap: () => launchUrl(_osmCopyright),
            ),
            ListRow(
              title: l10n.creditsTiles,
              leading: const RowTile(PindoroGlyph.layers),
            ),
            ListRow(
              title: l10n.creditsFont,
              leading: const RowTile(PindoroGlyph.book),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => showLicensePage(context: context),
            ),
          ],
        ),
        Text(l10n.creditsFix, style: body),
      ],
    );
  }
}
