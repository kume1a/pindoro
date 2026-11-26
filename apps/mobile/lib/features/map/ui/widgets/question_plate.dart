import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
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

/// What a street's sub-line says about it: its other script, and its area when
/// another street has its name (a Rustaveli Street in Tskneti, not Vake's).
List<String> streetNotes(
  WidgetRef ref,
  NamedStreet street,
  Settings? settings,
) => [
  ?otherScript(street, settings),
  if (ref.watch(namesakeAreaProvider).value?.call(street) case final area?)
    districtName(area, settings),
];

class QuestionPlate extends ConsumerWidget {
  const QuestionPlate({
    super.key,
    required this.street,
    required this.settings,
    required this.compact,
    this.retryDistance,
    this.guess,
    this.prompt,
    this.detail,
    this.glyph,
  });

  final NamedStreet street;
  final Settings? settings;
  final bool compact;
  final double? retryDistance;

  /// Guess first: "Guess first" over the name, this as the sub-line.
  final String? guess;

  /// The ask row instead of "Drop a pin on" ("Placement · 12 of 88").
  final String? prompt;

  /// Added to the sub-line ("1.4 km", "Heading south from …").
  final String? detail;

  /// The ask row's icon instead of the pin.
  final PindoroGlyph? glyph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final name = streetName(street, settings);
    final notes = streetNotes(ref, street, settings);
    final distance = retryDistance == null
        ? null
        : l10n.quizRetryPreviousDistance(formatDistance(retryDistance!, l10n));
    final (prompt, glyph) = switch ((guess, retryDistance)) {
      (_?, _) => (l10n.sessionGuessFirst, PindoroGlyph.hint),
      (_, _?) => (l10n.quizRetryPrompt, PindoroGlyph.reroute),
      _ => (this.prompt ?? l10n.quizPrompt, this.glyph ?? PindoroGlyph.pin),
    };
    return StreetPlate(
      name,
      compact: compact,
      prompt: prompt,
      promptGlyph: glyph,
      subline: [...notes, ?distance, ?guess, ?detail].join(' · ').nullIfEmpty,
      semanticLabel: notes.isEmpty
          ? l10n.a11yFindStreetName(name)
          : l10n.a11yFindStreet(name, notes.join(' · ')),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
