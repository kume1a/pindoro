import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Your landmarks (board V3-32): each with its kind and junction, delete
/// (asked first), and Add a landmark.
class LandmarksScreen extends ConsumerWidget {
  const LandmarksScreen({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PersonalLandmarkRow landmark,
  ) async {
    final l10n = context.l10n;
    final delete = await showDialog<bool>(
      context: context,
      builder: (_) => PindoroDialog(
        title: l10n.landmarksDeleteTitle(landmark.name),
        body: l10n.landmarksDeleteBody,
        primary: l10n.landmarksKeep,
        secondary: l10n.landmarksDeleteConfirm,
      ),
    );
    if (delete != true) return;
    ref.read(feedbackProvider).tap();
    await ref.read(learningDaoProvider).deletePersonalLandmark(landmark.id);
    ref.invalidate(personalLandmarksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final landmarks = ref.watch(personalLandmarksProvider).value ?? const [];
    final pack = ref.watch(packRepositoryProvider).value;
    final graph = ref.watch(roadGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final byNode = {
      for (final MapEntry(:key, :value)
          in pack?.junctionNodes().entries ?? const <MapEntry<int, int>>[])
        'n$value': key,
    };
    String? junctionOf(PersonalLandmarkRow l) =>
        switch ((graph, byNode[l.junctionId])) {
          (final g?, final j?) => junctionName(g, j, streets, settings),
          _ => null,
        };
    return PageScaffold(
      title: l10n.learnLandmarks,
      footer: PindoroButton(
        label: l10n.landmarksAdd,
        icon: PindoroGlyph.plus,
        onPressed: () => context.push(Routes.landmarkAdd),
      ),
      children: [
        if (landmarks.isEmpty)
          Text(
            l10n.landmarksEmpty,
            style: PindoroType.bodyMd.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          )
        else
          ListGroup(
            children: [
              for (final l in landmarks)
                ListRow(
                  leading: RowTile(landmarkGlyph(l.kind)),
                  title: l.name,
                  subtitle: [
                    landmarkKindName(l10n, l.kind),
                    ?junctionOf(l),
                  ].join(' · '),
                  trailing: PindoroIconButton(
                    glyph: PindoroGlyph.close,
                    semanticLabel: l10n.landmarksDelete(l.name),
                    onPressed: () => unawaited(_delete(context, ref, l)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
