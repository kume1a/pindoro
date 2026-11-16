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

/// The area picker's sheet, kept short so the map stays the main thing: the
/// modes, the title over the [count] with the [countAction] beside them, the
/// [help] line when there is one, one row of [content] and [next].
class AreaSheet extends StatelessWidget {
  const AreaSheet({
    super.key,
    required this.modes,
    required this.mode,
    required this.onMode,
    required this.title,
    required this.next,
    this.help,
    this.count,
    this.countAction,
    this.content,
  });

  final Map<AreaMode, String> modes;
  final AreaMode mode;
  final ValueChanged<AreaMode> onMode;
  final String title;
  final String? help;
  final String? count;

  /// Beside the title and count: the "All n" chip, or Try again offline.
  final Widget? countAction;

  /// One row: the chips (scrolling sideways) or the circle's slider.
  final Widget? content;
  final Widget next;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final help = this.help;
    final count = this.count;
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
          Row(
            spacing: PindoroSpace.s3,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                    ),
                    if (count != null)
                      Text(
                        count,
                        style: PindoroType.labelMd.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              ?countAction,
            ],
          ),
          if (help != null)
            Text(
              help,
              style: PindoroType.bodySm.copyWith(color: c.textSecondary),
            ),
          ?content,
          next,
        ],
      ),
    );
  }
}
