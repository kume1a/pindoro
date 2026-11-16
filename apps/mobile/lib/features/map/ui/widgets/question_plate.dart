import 'package:flutter/material.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The street's other script for a sub-line: English under a local name, the
/// local name under an English one; null when there is none.
String? otherScript(NamedStreet street, Settings? settings) {
  final name = streetName(street, settings);
  return settings?.streetNames == StreetNameMode.english
      ? (name == street.name ? null : street.name)
      : street.nameEn;
}

class QuestionPlate extends StatelessWidget {
  const QuestionPlate({
    super.key,
    required this.street,
    required this.settings,
    required this.compact,
    this.retryDistance,
    this.guess,
  });

  final NamedStreet street;
  final Settings? settings;
  final bool compact;
  final double? retryDistance;

  /// Guess first: "Guess first" over the name, this as the sub-line.
  final String? guess;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = streetName(street, settings);
    final other = otherScript(street, settings);
    final distance = retryDistance == null
        ? null
        : l10n.quizRetryPreviousDistance(formatDistance(retryDistance!, l10n));
    final (prompt, glyph) = switch ((guess, retryDistance)) {
      (_?, _) => (l10n.sessionGuessFirst, PindoroGlyph.hint),
      (_, _?) => (l10n.quizRetryPrompt, PindoroGlyph.reroute),
      _ => (l10n.quizPrompt, PindoroGlyph.pin),
    };
    return StreetPlate(
      name,
      compact: compact,
      prompt: prompt,
      promptGlyph: glyph,
      subline: [?other, ?distance, ?guess].join(' · ').nullIfEmpty,
      semanticLabel: other == null
          ? l10n.a11yFindStreetName(name)
          : l10n.a11yFindStreet(name, other),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
