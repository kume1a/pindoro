import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/setup/data/start_districts.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "Where do you want to start?" (canvas R4-51): a new player picks the
/// raion their course starts in. Nothing is saved before Start in.
class StartDistrictScreen extends ConsumerStatefulWidget {
  const StartDistrictScreen({super.key});

  @override
  ConsumerState<StartDistrictScreen> createState() =>
      _StartDistrictScreenState();
}

class _StartDistrictScreenState extends ConsumerState<StartDistrictScreen> {
  /// The picked raion's id; null keeps the first row.
  String? _picked;
  bool _busy = false;

  Future<void> _start(String cityId, String districtId) async {
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    await ref.read(progressDaoProvider).saveCourseStart(cityId, districtId);
    ref.invalidate(coursePlanProvider);
    if (mounted) context.go(Routes.path);
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packRepositoryProvider);
    if (!pack.hasValue) return PackPending(pack: pack);
    final data = ref.watch(startDistrictsProvider).value;
    if (data == null) return const Scaffold();
    final rows = data.rows;
    if (rows.isEmpty) {
      // A city without raions has no course to start: the Path says so.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.path);
      });
      return const Scaffold();
    }
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final city = data.city;
    final picked = rows.firstWhere(
      (r) => r.district.id == _picked,
      orElse: () => rows.first,
    );
    final pickedName = districtName(picked.district, settings);
    return PageScaffold(
      title: context.localName(ka: city.nameKa, en: city.nameEn),
      footer: PindoroButton(
        label: l10n.startIn(pickedName),
        onPressed: _busy ? null : () => _start(city.id, picked.district.id),
      ),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.startTitle,
            style: PindoroType.headlineMd.copyWith(color: c.textPrimary),
          ),
        ),
        Text(
          l10n.startBody,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        ListGroup(
          children: [
            for (final row in rows)
              () {
                final selected = row == picked;
                return Semantics(
                  container: true,
                  inMutuallyExclusiveGroup: true,
                  checked: selected,
                  child: ListRow(
                    title: districtName(row.district, settings),
                    subtitle: [
                      l10n.startStreets(row.streets),
                      l10n.startHint(switch (row.hint) {
                        StartHint.near => 'near',
                        StartHint.centre => 'centre',
                        StartHint.direction => row.direction.name,
                      }),
                    ].join(' · '),
                    trailing: selected
                        ? PindoroIcon(
                            PindoroGlyph.checkCircle,
                            color: c.primaryText,
                          )
                        : null,
                    onTap: () {
                      ref.read(feedbackProvider).tap();
                      setState(() => _picked = row.district.id);
                    },
                  ),
                );
              }(),
          ],
        ),
        Text(
          l10n.startCount(rows.length),
          style: PindoroType.labelMd.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}
