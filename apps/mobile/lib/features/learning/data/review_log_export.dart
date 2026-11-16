import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:share_plus/share_plus.dart';

/// Writes the whole review log as CSV and opens the share sheet
/// (docs/learning/SPEC.md §12). Tests override it.
final reviewLogExportProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final now = ref.read(clockProvider)();
    final csv = reviewLogCsv(await ref.read(learningDaoProvider).log());
    final day = startOfDay(now).toIso8601String().substring(0, 10);
    final dir = await getTemporaryDirectory();
    final file = await File(
      '${dir.path}/pindoro-review-log-$day.csv',
    ).writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]),
    );
  };
});
