import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/map/ui/widgets/street_match_row.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A street typed by name, one after another: the field, any [error], and the street the
/// text suggests ([match]) to take with [onMatch].
class StreetEntry extends StatelessWidget {
  const StreetEntry({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    required this.onSubmitted,
    required this.match,
    required this.onMatch,
    this.error,
  });

  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final NamedStreet? match;
  final VoidCallback onMatch;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final match = this.match;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s2,
      children: [
        SearchField(
          controller: controller,
          placeholder: placeholder,
          clearLabel: l10n.commonClear,
          glyph: PindoroGlyph.signpost,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          keepFocus: true,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmitted(),
        ),
        if (error case final error?)
          Text(
            error,
            style: PindoroType.bodySm.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          ),
        if (match != null)
          StreetMatchRow(
            match,
            note: l10n.sessionCrossingsMatch,
            onTap: onMatch,
          ),
      ],
    );
  }
}
