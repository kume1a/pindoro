import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/learning/data/tuning.dart';
import 'package:pindoro/features/settings/ui/widgets/settings_rows.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Memory model (SPEC §12, §16.9): the calibration check, the FSRS weights
/// fitted with `just fsrs-fit` (pasted here, used from the next launch) and
/// whether tier C relief is on.
class MemoryModelScreen extends ConsumerStatefulWidget {
  const MemoryModelScreen({super.key});

  @override
  ConsumerState<MemoryModelScreen> createState() => _MemoryModelScreenState();
}

class _MemoryModelScreenState extends ConsumerState<MemoryModelScreen> {
  final _weights = TextEditingController();

  @override
  void dispose() {
    _weights.dispose();
    super.dispose();
  }

  Future<void> _save(String? json, {required String toast}) async {
    await ref.read(settingsDaoProvider).setFsrsWeights(json);
    if (mounted) showToast(context, toast);
  }

  Future<void> _use() async {
    final l10n = context.l10n;
    final weights = FsrsWeights.parse(_weights.text);
    if (weights == null) return showToast(context, l10n.memoryWeightsInvalid);
    _weights.clear();
    await _save(jsonEncode(weights), toast: l10n.memoryWeightsSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final model = ref.watch(memoryModelProvider).value;
    final stored = ref.watch(settingsProvider).value?.fsrsWeights;
    String percent(double share) => formatNumber((share * 100).round());
    final bins = model?.bins ?? const <CalibrationBin>[];
    return PageScaffold(
      title: l10n.memoryModelTitle,
      children: [
        SectionTitle(l10n.memoryCalibration),
        if (model != null && bins.isEmpty)
          Text(
            l10n.memoryCalibrationEmpty,
            style: PindoroType.bodyMd.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          )
        else if (bins.isNotEmpty) ...[
          ForecastBars(
            counts: [for (final b in bins) (b.recalled * 100).round()],
            title: l10n.memoryCalibrationChart,
            average: l10n.memoryCalibrationHealthy,
            startLabel: l10n.lessonPercent(percent(bins.first.from)),
            endLabel: l10n.lessonPercent(percent(bins.last.from)),
            semanticsLabel: l10n.memoryCalibrationChart,
            highlightFirst: false,
          ),
          ListGroup(
            children: [
              for (final b in bins)
                ListRow(
                  title: l10n.memoryBin(percent(b.from), percent(b.to)),
                  subtitle: l10n.memoryBinRecalled(
                    percent(b.recalled),
                    b.reviews,
                  ),
                  trailing: switch (b.calibrated) {
                    true => PindoroIcon(
                      PindoroGlyph.checkCircle,
                      semanticLabel: l10n.memoryCalibrationHealthy,
                    ),
                    false => PindoroIcon(
                      PindoroGlyph.target,
                      semanticLabel: l10n.memoryBinOff,
                    ),
                    null => null,
                  },
                ),
            ],
          ),
        ],
        SectionTitle(l10n.memoryWeights),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.chart),
              title: FsrsWeights.fitted
                  ? l10n.memoryWeightsFitted
                  : l10n.memoryWeightsDefault,
              subtitle: l10n.memoryWeightsReviews(
                formatNumber(model?.reviews ?? 0),
                formatNumber(LearningConfig.fitMinReviews),
              ),
            ),
          ],
        ),
        LabelledField(
          label: l10n.memoryWeightsPaste,
          help: l10n.memoryWeightsHelp,
          child: SearchField(
            controller: _weights,
            placeholder: '[0.212, 1.2931, …]',
            clearLabel: l10n.commonClear,
            glyph: PindoroGlyph.edit,
            autocorrect: false,
            textInputAction: TextInputAction.done,
          ),
        ),
        PindoroButton(label: l10n.memoryWeightsUse, onPressed: _use),
        if (stored != null)
          PindoroButton(
            label: l10n.memoryWeightsReset,
            variant: PindoroButtonVariant.tertiary,
            onPressed: () => _save(null, toast: l10n.memoryWeightsSaved),
          ),
        SectionTitle(l10n.memoryRelief),
        if (model case final m?)
          ListGroup(
            children: [
              ListRow(
                leading: const RowTile(PindoroGlyph.timer),
                title: m.relief.on ? l10n.memoryReliefOn : l10n.memoryReliefOff,
                subtitle: l10n.memoryReliefAverage(
                  formatNumber((m.relief.meanS / 60).round()),
                  formatNumber(m.minutesPerDay),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
