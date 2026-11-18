import 'package:flutter/material.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// An intro's screen (a new street, a leech, a new place): the [map] under
/// the [topBar] and the step's [plate], and its Intro [sheet] docked at the
/// bottom. Plate and sheet rise in anew per [stepKey].
class IntroScaffold extends StatelessWidget {
  const IntroScaffold({
    super.key,
    required this.stepKey,
    required this.map,
    required this.topBar,
    required this.plate,
    required this.sheet,
  });

  final Object stepKey;
  final Widget Function(MapInsets insets) map;
  final Widget topBar;
  final Widget plate;
  final Widget sheet;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MapLayout(
      map: map,
      top: Column(
        spacing: PindoroSpace.s2,
        children: [
          topBar,
          RiseSwitcher(
            child: KeyedSubtree(key: ValueKey(stepKey), child: plate),
          ),
        ],
      ),
      bottom: RevealDock(revealKey: stepKey, sheet: sheet),
    ),
  );
}
