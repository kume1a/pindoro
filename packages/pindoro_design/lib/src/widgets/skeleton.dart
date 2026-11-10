import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';

/// A placeholder block while content loads (`.pd-skel`): sunken, with a
/// raised shimmer crossing it (`motion.shimmer`); still under reduce motion.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.radius = PindoroRadius.md,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: PindoroMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: ColoredBox(
            color: c.surfaceSunken,
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (context, _) {
                if (!_shimmer.isAnimating) return const SizedBox.expand();
                // Slides from fully left of the block to fully right of it.
                final x = Curves.easeInOut.transform(_shimmer.value) * 2 - 1;
                return FractionalTranslation(
                  translation: Offset(x, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          c.surfaceRaised.withValues(alpha: 0),
                          c.surfaceRaised.withValues(
                            alpha: PindoroOpacity.shimmer,
                          ),
                          c.surfaceRaised.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
