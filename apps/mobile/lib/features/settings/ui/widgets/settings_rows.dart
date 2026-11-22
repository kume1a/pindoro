import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A control under its label, with an optional help line.
class LabelledField extends StatelessWidget {
  const LabelledField({
    super.key,
    required this.label,
    required this.child,
    this.help,
  });

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
        if (help case final help?)
          Text(
            help,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
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

/// Street names: the city's script or English.
class StreetNamesField extends ConsumerWidget {
  const StreetNamesField({super.key, required this.settings, this.help});

  final Settings settings;
  final String? help;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return LabelledField(
      label: l10n.settingsStreetNames,
      help: help,
      child: SegmentedControl(
        segments: {
          StreetNameMode.local: l10n.settingsStreetNamesLocal,
          StreetNameMode.english: l10n.settingsStreetNamesEnglish,
        },
        selected: settings.streetNames,
        onChanged: (v) {
          ref.read(feedbackProvider).tap();
          ref.read(settingsDaoProvider).setStreetNames(v);
        },
      ),
    );
  }
}

/// The 19:00 reminder; on asks for notification permission first.
class ReminderRow extends ConsumerWidget {
  const ReminderRow({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToggleRow(
    title: context.l10n.settingsReminder,
    subtitle: context.l10n.settingsReminderSubtitle(
      MaterialLocalizations.of(context).formatTimeOfDay(
        const TimeOfDay(hour: StreakRules.reminderHour, minute: 0),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      ),
    ),
    glyph: PindoroGlyph.bell,
    value: settings.reminder,
    onChanged: (on) => _setReminder(context, ref, on: on),
  );
}

/// On asks for notification permission first; without it the switch stays
/// off and a toast says where to allow it. Off cancels the scheduled one.
Future<void> _setReminder(
  BuildContext context,
  WidgetRef ref, {
  required bool on,
}) async {
  final dao = ref.read(settingsDaoProvider);
  final reminders = ref.read(remindersProvider);
  ref.read(feedbackProvider).tap();
  if (!on) {
    await dao.setReminder(on: false);
    await reminders.cancel();
  } else if (await reminders.requestPermission()) {
    await dao.setReminder(on: true);
  } else if (context.mounted) {
    showToast(context, context.l10n.settingsReminderDenied);
  }
}

/// "Warn me over the limit by" (SPEC §16.23 item 127): 0 to the most km/h, saved when let go.
class SpeedToleranceField extends ConsumerStatefulWidget {
  const SpeedToleranceField({super.key, required this.kmh});

  final int kmh;

  @override
  ConsumerState<SpeedToleranceField> createState() =>
      _SpeedToleranceFieldState();
}

class _SpeedToleranceFieldState extends ConsumerState<SpeedToleranceField> {
  late double _kmh = widget.kmh.toDouble();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = l10n.settingsSpeedToleranceValue(_kmh.round());
    return LabelledField(
      label: '${l10n.settingsSpeedTolerance}: $label',
      help: l10n.settingsSpeedToleranceNote,
      child: Slider(
        value: _kmh,
        max: LearningConfig.speedToleranceMaxKmh.toDouble(),
        divisions: LearningConfig.speedToleranceMaxKmh,
        label: label,
        semanticFormatterCallback: (v) =>
            l10n.settingsSpeedToleranceValue(v.round()),
        onChanged: (v) => setState(() => _kmh = v),
        onChangeEnd: (v) => unawaited(
          ref.read(settingsDaoProvider).setSpeedTolerance(v.round()),
        ),
      ),
    );
  }
}

/// Home and Work for drives (SPEC §16.23 items 120–121), each opening its picker.
class DrivePlacesGroup extends ConsumerWidget {
  const DrivePlacesGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final places = ref.watch(drivePlacesProvider).value;
    Widget row(bool home, DriveTarget? place) => ListRow(
      leading: RowTile(home ? PindoroGlyph.home : PindoroGlyph.briefcase),
      title: home ? l10n.driveHome : l10n.driveWork,
      subtitle: place == null ? l10n.driveNotSet : targetName(place, settings),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () =>
          unawaited(context.push(Routes.drivePlaceOf(home ? 'home' : 'work'))),
    );
    return ListGroup(
      children: [row(true, places?.home), row(false, places?.work)],
    );
  }
}
