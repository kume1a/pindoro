import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A play screen's top bar (a round, a lesson, a Final drive): ✕ to leave,
/// the question bar and the XP so far.
class PlayBar extends StatelessWidget {
  const PlayBar({
    super.key,
    required this.leaveLabel,
    required this.onLeave,
    required this.tiers,
    required this.total,
    required this.barLabel,
    required this.xp,
    required this.xpLabel,
  });

  final String leaveLabel;
  final VoidCallback onLeave;

  /// The filled segments, of [total].
  final List<Tier> tiers;
  final int total;
  final String barLabel;
  final int xp;

  /// Reads the formatted XP out.
  final String Function(String xp) xpLabel;

  @override
  Widget build(BuildContext context) {
    final formatted = formatNumber(xp);
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: leaveLabel,
          onPressed: onLeave,
        ),
        Expanded(
          child: QuestionBar(
            tiers: tiers,
            total: total,
            semanticLabel: barLabel,
          ),
        ),
        Pill(
          label: formatted,
          icon: PindoroGlyph.xp,
          iconColor: PindoroTheme.of(context).colors.xpFill,
          floating: true,
          semanticLabel: xpLabel(formatted),
        ),
      ],
    );
  }
}

/// Asks before leaving a play screen: [stay] or [leave]. True to leave.
Future<bool> confirmLeave(
  BuildContext context, {
  required String title,
  required String body,
  required String stay,
  required String leave,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: title,
        body: body,
        primary: stay,
        secondary: leave,
      ),
    ) ??
    false;
