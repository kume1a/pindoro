import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/setup/data/area_tree.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';

enum AreaMode { districts, circle, rectangle }

/// "0 of 104 areas" before a pick, then "2 areas · 312 streets".
String areaCountLine(
  AppLocalizations l10n,
  int total,
  Set<String> picked,
  Map<String, Set<String>>? streets,
) {
  if (picked.isEmpty || streets == null) {
    return l10n.areaCount(total, picked.length);
  }
  final n = streetCount(streets, picked);
  return '${l10n.areaPickedCount(picked.length)} · '
      '${l10n.areaStreetCount(n, formatNumber(n))}';
}

class AreaSheet extends StatelessWidget {
  const AreaSheet({
    super.key,
    required this.modes,
    required this.mode,
    required this.onMode,
    required this.title,
    required this.help,
    required this.next,
    this.count,
    this.all,
    this.content,
  });

  final Map<AreaMode, String> modes;
  final AreaMode mode;
  final ValueChanged<AreaMode> onMode;
  final String title;
  final String help;
  final String? count;

  /// The "All n" chip that opens every area, on the count line.
  final Widget? all;
  final Widget? content;
  final Widget next;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return BottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          if (modes.length > 1)
            SegmentedControl(
              segments: modes,
              selected: mode,
              onChanged: onMode,
            ),
          Text(
            title,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          if (count != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    count!,
                    style: PindoroType.labelMd.copyWith(color: c.textSecondary),
                  ),
                ),
                ?all,
              ],
            ),
          Text(
            help,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
          if (content != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.25,
              ),
              child: SingleChildScrollView(child: content),
            ),
          next,
        ],
      ),
    );
  }
}
