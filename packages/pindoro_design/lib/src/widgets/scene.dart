import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'skeleton.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// A street-level photo for the scene cards (`.pd-scene`): the [photo]
/// 260 dp tall, cropped to fill, then its [caption] and [attribution] in
/// `label.sm`, on a `radius.xl` card with an `elevation.2` lip. A null
/// [photo] is loading (a skeleton). [semanticsLabel] describes what the photo
/// shows, never the answer; [onAttribution] opens the photo's page at its
/// source.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.photo,
    required this.caption,
    required this.attribution,
    required this.semanticsLabel,
    this.onAttribution,
  });

  static const double photoHeight = 260;

  final ImageProvider? photo;
  final String caption;
  final String attribution;
  final String semanticsLabel;
  final VoidCallback? onAttribution;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final meta = PindoroType.labelSm.copyWith(color: c.textSecondary);
    final photo = this.photo;
    final credit = Text(attribution, style: meta);
    return LipBox(
      lipHeight: PindoroElevation.e2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PindoroRadius.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo == null)
              const Skeleton(height: photoHeight, radius: 0)
            else
              Semantics(
                image: true,
                label: semanticsLabel,
                child: Image(
                  image: photo,
                  height: photoHeight,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: c.surfaceSunken,
                    child: const SizedBox(height: photoHeight),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: PindoroSpace.s2,
                horizontal: PindoroSpace.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caption, style: meta),
                  if (onAttribution == null)
                    credit
                  else
                    Tappable(onTap: onAttribution, child: credit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
