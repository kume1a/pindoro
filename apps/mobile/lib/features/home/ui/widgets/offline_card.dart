import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// While the bundled Vake pack stands in for [city]: Download gets the whole
/// city.
class OfflineCard extends StatelessWidget {
  const OfflineCard({super.key, required this.city, required this.onDownload});

  final String city;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Text(
            l10n.homeOfflineTitle,
            style: PindoroType.titleMd.copyWith(color: c.textPrimary),
          ),
          Text(
            l10n.packDownloadBody,
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
          PindoroButton(
            label: l10n.homeOfflineDownload(city),
            icon: PindoroGlyph.download,
            variant: PindoroButtonVariant.secondary,
            onPressed: onDownload,
          ),
        ],
      ),
    );
  }
}
