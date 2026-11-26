import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The street a typed name suggests (`suggestStreet`), as a row to take it:
/// its name, its notes (other script, the area of a shared name) and any [note].
class StreetMatchRow extends ConsumerWidget {
  const StreetMatchRow(
    this.street, {
    super.key,
    required this.onTap,
    this.note,
    this.check,
  });

  final NamedStreet street;
  final VoidCallback onTap;
  final String? note;
  final CheckState? check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final subtitle = [...streetNotes(ref, street, settings), ?note].join(' · ');
    return ListRow(
      leading: const RowTile(PindoroGlyph.signpost),
      title: streetName(street, settings),
      subtitle: subtitle.isEmpty ? null : subtitle,
      check: check,
      onTap: onTap,
    );
  }
}
