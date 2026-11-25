import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/labels.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// "Aghmashenebeli Ave × Marjanishvili St": the streets meeting at
/// [junction], by their shown names; null where only connectors meet.
String? junctionName(
  RoadGraph graph,
  int junction,
  Map<String, NamedStreet> streets,
  Settings? settings,
) {
  final names = {
    for (final e in graph.edgesAt(junction))
      if (streets[e.streetId] case final s?) streetName(s, settings),
  }.toList()..sort();
  return names.isEmpty ? null : names.join(' × ');
}

/// "At Chavchavadze Avenue": another street meeting [on] at [junction];
/// null where none does.
String? crossingAt(
  RoadGraph graph,
  int junction,
  NamedStreet on,
  Map<String, NamedStreet> streets,
  Settings? settings,
) {
  final other = {
    for (final e in graph.edgesAt(junction))
      if (streets[e.streetId] case final s? when s != on)
        streetName(s, settings),
  }.toList()..sort();
  return other.firstOrNull;
}
