import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/config.dart';
import '../../app/router.dart';
import '../map/pindoro_map.dart';
import '../pack/sqlite_pack_repository.dart';

/// M0 placeholder quiz: the map over the fixture district with a debug
/// button that reveals a random street and measures the pin against it.
class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: ref
        .watch(packRepositoryProvider)
        .when(
          data: (pack) => _DebugQuiz(pack),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not open pack: $e')),
        ),
  );
}

class _DebugQuiz extends StatefulWidget {
  const _DebugQuiz(this.pack);

  final PackRepository pack;

  @override
  State<_DebugQuiz> createState() => _DebugQuizState();
}

class _DebugQuizState extends State<_DebugQuiz> {
  late final District _district = widget.pack.districts().firstWhere(
    (d) => d.id == AppConfig.fixtureDistrictId,
  );
  late final List<Street> _streets = widget.pack.streets(
    districtId: _district.id,
  );
  final _random = Random();
  LatLng? _pin;
  Street? _truth;

  @override
  Widget build(BuildContext context) {
    final pin = _pin, truth = _truth;
    final nearest = pin == null || truth == null
        ? null
        : pointToPolylineDistance(pin, truth.geometry);
    return Stack(
      children: [
        PindoroMap(
          initialCenter: _district.center,
          pin: pin,
          truth: truth?.geometry,
          measure: nearest == null ? null : (pin!, nearest.nearestPoint),
          onTap: (p) => setState(() => _pin = p),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PindoroTokens.spaceMd),
            child: Column(
              spacing: PindoroTokens.spaceSm,
              children: [
                StreetPlate(truth?.nameKa ?? 'Tap the map to drop a pin'),
                if (nearest != null)
                  Text(
                    '${nearest.distanceMeters.round()} m',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const Spacer(),
                if (kDebugMode)
                  PindoroButton(
                    label: 'Highlight a random street',
                    variant: PindoroButtonVariant.secondary,
                    onPressed: () => setState(
                      () => _truth = _streets[_random.nextInt(_streets.length)],
                    ),
                  ),
                PindoroButton(
                  label: 'Finish',
                  onPressed: () => context.go(Routes.results),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
