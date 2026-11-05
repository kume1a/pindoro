import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';

/// Tier badge, distance and xp; with [name] it is a results-list row.
class AnswerRow extends StatelessWidget {
  const AnswerRow(this.answer, {super.key, this.name});

  final Answer answer;
  final String? name;

  @override
  Widget build(BuildContext context) => Row(
    spacing: PindoroTokens.spaceSm,
    children: [
      FeedbackBadge(answer.tier),
      if (name case final name?)
        Expanded(child: Text(name))
      else
        const Spacer(),
      Text(
        '${answer.distanceM.round()} m · +${answer.xp} xp',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}
