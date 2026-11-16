import 'cards.dart';

const _columns = [
  'id',
  'ts',
  'item_id',
  'type',
  'format',
  'rating',
  'distance_m',
  'snap_id',
  'rt_ms',
  'elapsed_days',
  'r_before',
  's_before',
  'd_before',
  'session_id',
  'source',
];

/// The review log as CSV (RFC 4180, CRLF) with SPEC §2.2's columns, for the optimiser and for
/// checking calibration. [log] is oldest first; `id` numbers it from 1, as the append-only table
/// does.
String reviewLogCsv(Iterable<LogEntry> log) {
  final out = StringBuffer()..write('${_columns.join(',')}\r\n');
  var id = 0;
  for (final e in log) {
    final row = <Object?>[
      ++id,
      e.ts.toUtc().toIso8601String(),
      e.itemId,
      e.type.name.toUpperCase(),
      e.format.name,
      e.rating.grade,
      e.distanceM,
      e.snapId,
      e.rtMs,
      e.elapsedDays,
      e.rBefore,
      e.sBefore,
      e.dBefore,
      e.sessionId,
      e.source.name,
    ];
    out.write('${row.map(_field).join(',')}\r\n');
  }
  return out.toString();
}

String _field(Object? value) {
  final text = value?.toString() ?? '';
  return text.contains(RegExp('[",\r\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}
