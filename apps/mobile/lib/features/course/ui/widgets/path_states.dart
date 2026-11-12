import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Loading the course (canvas R4-10 `loading`): nothing for 300 ms, then a
/// skeleton signpost and stops; from 2 s also thinking Pindo, what is
/// happening and the lane loader.
class PathLoading extends StatefulWidget {
  const PathLoading({super.key, required this.city});

  final String city;

  @override
  State<PathLoading> createState() => _PathLoadingState();
}

class _PathLoadingState extends State<PathLoading> {
  /// The board's skeleton stops: their centres' x from the middle and their
  /// tops under the signpost's top.
  static const List<(double, double)> _stops = [
    (0, 95),
    (-67, 199),
    (0, 511),
    (67, 615),
  ];
  static const double _cardTop = 313;

  bool _skeletons = false;
  bool _card = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _timers.addAll([
      Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _skeletons = true);
      }),
      Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _card = true);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_skeletons) return const SizedBox.expand();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: ContentColumn(
        child: SizedBox(
          height: _stops.last.$2 + PindoroSize.tapMin + PindoroSpace.s4,
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                child: Skeleton(height: 64, radius: PindoroRadius.lg),
              ),
              for (final (dx, top) in _stops)
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: const Skeleton(
                        width: 56,
                        height: 56,
                        radius: PindoroRadius.full,
                      ),
                    ),
                  ),
                ),
              if (_card)
                Positioned(
                  top: _cardTop,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    liveRegion: true,
                    child: LipBox(
                      padding: const EdgeInsets.all(PindoroSpace.s4),
                      child: Row(
                        spacing: PindoroSpace.s3,
                        children: [
                          const Pindo(PindoExpression.thinking, height: 74),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: PindoroSpace.s2,
                              children: [
                                Text(
                                  l10n.pathLoadingTitle,
                                  style: PindoroType.titleMd.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  l10n.pathLoadingBody(widget.city),
                                  style: PindoroType.bodySm.copyWith(
                                    color: c.textSecondary,
                                  ),
                                ),
                                const LaneLoader(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PindoroSpace.s4),
        child: ContentColumn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s4,
            children: [
              const Pindo(PindoExpression.encouraging, height: 96),
              Text(
                text,
                textAlign: TextAlign.center,
                style: PindoroType.titleMd.copyWith(color: c.textPrimary),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class PathLoadError extends StatelessWidget {
  const PathLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Message(
      text: l10n.pathLoadError,
      actions: [
        PindoroButton(label: l10n.commonTryAgain, onPressed: onRetry),
        PindoroButton(
          label: l10n.pathOpenFreePlay,
          variant: PindoroButtonVariant.tertiary,
          onPressed: () => context.go(Routes.home),
        ),
      ],
    );
  }
}

class PathNoDistricts extends StatelessWidget {
  const PathNoDistricts({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Message(
      text: l10n.pathNoDistricts,
      actions: [
        PindoroButton(
          label: l10n.pathOpenFreePlay,
          onPressed: () => context.go(Routes.home),
        ),
      ],
    );
  }
}
