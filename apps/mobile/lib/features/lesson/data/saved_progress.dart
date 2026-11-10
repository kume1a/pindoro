import 'dart:convert';

import 'package:pindoro_core/pindoro_core.dart';

/// Where a saved lesson stands: its step and its answers.
typedef SavedProgress = ({int index, List<SavedAnswer> answers});

/// [run]'s step and answers as `saved_lesson.progress` JSON.
String encodeProgress(LessonRun run) => jsonEncode({
  'index': run.index,
  'answers': [
    for (final a in run.saved)
      {
        'step': a.step,
        'street': a.streetId,
        'tier': a.tier.name,
        'xp': a.xp,
        'distance': a.distanceM,
        'at': a.at.toIso8601String(),
      },
  ],
});

/// The progress [json] holds; null when it can't be read.
SavedProgress? decodeProgress(String json) {
  try {
    final map = jsonDecode(json) as Map<String, Object?>;
    return (
      index: map['index']! as int,
      answers: [
        for (final a in (map['answers']! as List).cast<Map<String, Object?>>())
          (
            step: a['step']! as int,
            streetId: a['street']! as String,
            tier: Tier.values.byName(a['tier']! as String),
            xp: a['xp']! as int,
            distanceM: (a['distance'] as num?)?.toDouble(),
            at: DateTime.parse(a['at']! as String),
          ),
      ],
    );
  } on Object {
    // ponytail: any malformed save just starts the lesson over.
    return null;
  }
}
