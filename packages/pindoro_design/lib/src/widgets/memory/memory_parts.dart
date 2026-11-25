import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';

/// A chart's first and last labels, under its two ends.
class EndLabels extends StatelessWidget {
  const EndLabels(this.start, this.end, {super.key, required this.style});

  final String start;
  final String end;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    spacing: PindoroSpace.s3,
    children: [
      Flexible(child: Text(start, style: style)),
      Flexible(
        child: Text(end, style: style, textAlign: TextAlign.end),
      ),
    ],
  );
}

String plainNumber(int n) => '$n';
