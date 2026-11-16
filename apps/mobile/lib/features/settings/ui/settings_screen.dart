import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/account/ui/account_group.dart';
import 'package:pindoro/features/learning/data/review_log_export.dart';
import 'package:pindoro/features/pack/data/app_update.dart';
import 'package:pindoro/features/settings/ui/widgets/settings_rows.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:url_launcher/url_launcher.dart';

/// Language, street names, the way to the learning settings, theme, sound,
/// haptics, the account; changes apply at once.
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
        LabelledField(
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
        StreetNamesField(
          settings: settings,
          help: l10n.settingsStreetNamesHelp,
        ),
        ListGroup(
          children: [
            ListRow(
              title: l10n.learnSettingsTitle,
              subtitle: l10n.settingsLearningSubtitle,
              leading: const RowTile(PindoroGlyph.road),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.learnSettings),
            ),
          ],
        ),
        SectionTitle(l10n.settingsDisplay),
        LabelledField(
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
            ToggleRow(
              title: l10n.settingsSound,
              subtitle: l10n.settingsSoundSubtitle,
              glyph: settings.sound
                  ? PindoroGlyph.soundOn
                  : PindoroGlyph.soundOff,
              value: settings.sound,
              // Turning sound on plays the tap once to show it.
              onChanged: (v) {
                if (v) ref.read(soundsProvider).play(Sound.tap);
                save(() => dao.setSound(on: v));
              },
            ),
            ToggleRow(
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
        SectionTitle(l10n.settingsAccount),
        const AccountGroup(),
        SectionTitle(l10n.settingsAbout),
        ListGroup(
          children: [
            if (ref.watch(packageInfoProvider).value case final info?)
              _VersionRow(info, update: ref.watch(appUpdateProvider).value),
            ListRow(
              title: l10n.creditsTitle,
              leading: const RowTile(PindoroGlyph.map),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.credits),
            ),
            ListRow(
              title: l10n.settingsExportLog,
              leading: const RowTile(PindoroGlyph.share),
              onTap: () => _exportLog(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shares the review log as CSV; a failure says so in a toast.
Future<void> _exportLog(BuildContext context, WidgetRef ref) async {
  ref.read(feedbackProvider).tap();
  try {
    await ref.read(reviewLogExportProvider)();
  } on Exception {
    if (context.mounted) {
      showToast(context, context.l10n.settingsExportLogFailed);
    }
  }
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

/// This build's version; while a newer one is out, a tap downloads it.
class _VersionRow extends StatelessWidget {
  const _VersionRow(this.info, {required this.update});

  final PackageInfo info;
  final Uri? update;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final url = update;
    return ListRow(
      title: l10n.settingsVersion('${info.version} (${info.buildNumber})'),
      subtitle: url == null ? null : l10n.settingsUpdate,
      leading: const RowTile(PindoroGlyph.info),
      onTap: url == null
          ? null
          : () => launchUrl(url, mode: LaunchMode.externalApplication),
    );
  }
}
