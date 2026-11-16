import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

void main() {
  final first = LogEntry(
    ts: DateTime.utc(2026, 3, 2, 9, 0, 5),
    itemId: 'P:abc',
    format: ReviewFormat.retrieval1,
    rating: Rating.good,
    source: ReviewSource.session,
    distanceM: 42.5,
    snapId: 'abc',
    rtMs: 5400,
    sessionId: 's1',
  );
  final second = LogEntry(
    ts: DateTime(2026, 3, 4, 10),
    itemId: 'P:abc',
    format: ReviewFormat.review,
    rating: Rating.again,
    source: ReviewSource.session,
    elapsedDays: 2.04,
    rBefore: 0.91,
    sBefore: 2.3065,
    dBefore: 2.118,
    sessionId: 'has,comma "and quotes"',
  );

  test('has every SPEC §2.2 review_log column, in order', () {
    final lines = reviewLogCsv([first, second]).split('\r\n');
    expect(
      lines.first,
      'id,ts,item_id,type,format,rating,distance_m,snap_id,rt_ms,elapsed_days,'
      'r_before,s_before,d_before,session_id,source',
    );
  });

  test('one row per entry, numbered from 1, UTC times, blanks for nulls', () {
    final lines = reviewLogCsv([first, second]).split('\r\n');
    expect(lines, hasLength(4));
    expect(lines.last, isEmpty);
    expect(
      lines[1],
      '1,2026-03-02T09:00:05.000Z,P:abc,P,retrieval1,3,42.5,abc,5400,,,,,s1,session',
    );
    expect(
      lines[2],
      startsWith(
        '2,${second.ts.toUtc().toIso8601String()},P:abc,P,review,1,,,,',
      ),
    );
    expect(
      lines[2],
      contains(',2.04,0.91,2.3065,2.118,"has,comma ""and quotes""",session'),
    );
  });

  test('an empty log is just the header', () {
    expect(reviewLogCsv(const []).split('\r\n'), hasLength(2));
  });
}
