import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/settings/ui/widgets/settings_rows.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Learning settings (board V3-60 `learning`): minutes a day, home and work,
/// your landmarks, street names, the reminder and the memory model.
class LearnSettingsScreen extends ConsumerWidget {
  const LearnSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const Scaffold();
    final now = ref.watch(clockProvider)();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final perDay = LearningConfig.newPerDay[settings.minutesPerDay] ?? 0;
    final by = switch (ref.watch(unseenCoreProvider).value) {
      final unseen? => wholeCityBy(
        unseenCore: unseen,
        newPerDay: perDay,
        now: now,
      ),
      null => null,
    };
    final city = ref.watch(learnCityProvider).value;
    final districts = {
      for (final d
          in ref.watch(packRepositoryProvider).value?.districts() ??
              const <District>[])
        d.id: d,
    };
    String? nameOf(String? id) => switch (districts[id]) {
      final d? => districtName(d, settings),
      null => null,
    };
    final home = nameOf(city?.homeId);
    final work = nameOf(city?.workId);
    return PageScaffold(
      title: l10n.learnSettingsTitle,
      children: [
        SectionTitle(l10n.learnSettingsSection),
        LabelledField(
          label: l10n.learnTimeADay,
          help: by == null
              ? null
              : l10n.learnPace(
                  formatNumber(perDay),
                  DateFormat.yMMM(locale).format(by),
                ),
          child: SegmentedControl(
            segments: {
              for (final m in LearningConfig.newPerDay.keys)
                m: l10n.sessionMinutes(m),
            },
            selected: settings.minutesPerDay,
            onChanged: (m) {
              ref.read(feedbackProvider).tap();
              ref.read(settingsDaoProvider).setMinutesPerDay(m);
            },
          ),
        ),
        SectionTitle(l10n.learnWhereYouStart),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.home),
              title: l10n.learnHome,
              subtitle: home == null
                  ? l10n.learnAnchorUnset
                  : l10n.learnHomeSubtitle(home),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.anchorOf('home')),
            ),
            ListRow(
              leading: const RowTile(PindoroGlyph.briefcase),
              title: l10n.learnWork,
              subtitle: work == null
                  ? l10n.learnAnchorUnset
                  : l10n.learnWorkSubtitle(work),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.anchorOf('work')),
            ),
          ],
        ),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.fuelStation),
              title: l10n.learnLandmarks,
              subtitle: l10n.learnLandmarksSubtitle(
                ref.watch(personalLandmarksProvider).value?.length ?? 0,
              ),
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.landmarks),
            ),
          ],
        ),
        StreetNamesField(settings: settings),
        ListGroup(children: [ReminderRow(settings: settings)]),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.chart),
              title: l10n.memoryModelTitle,
              subtitle: l10n.memoryModelSubtitle,
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => context.push(Routes.memoryModel),
            ),
          ],
        ),
      ],
    );
  }
}
