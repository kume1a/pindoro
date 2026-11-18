import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Opens Google Street View at [spot] in the Maps app.
class StreetViewButton extends ConsumerWidget {
  const StreetViewButton(this.spot, {super.key});

  final StreetViewSpot spot;

  /// Taps, then opens Street View at [spot]: this button, or an Intro
  /// sheet's own link.
  static void open(WidgetRef ref, StreetViewSpot spot) {
    ref.read(feedbackProvider).tap();
    unawaited(GoogleMaps.open(GoogleMaps.streetView(spot)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PindoroIconButton(
    glyph: PindoroGlyph.eye,
    semanticLabel: context.l10n.streetView,
    onPressed: () => open(ref, spot),
  );
}
