import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/setup/data/area_tree.dart';
import 'package:pindoro/features/setup/ui/widgets/area_sheet.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The 90 % sheet with every area: a checkbox row per district, its quarters
/// and neighbourhoods folded under it, and a search over both scripts.
class AllAreasSheet extends StatefulWidget {
  const AllAreasSheet({
    super.key,
    required this.tree,
    required this.names,
    required this.streets,
    required this.picked,
    required this.onToggle,
    required this.onClear,
  });

  final AreaTree tree;

  /// Each area's display name, by id.
  final Map<String, String> names;

  /// Each area's streets, for the counts; null while they load.
  final Map<String, Set<String>>? streets;
  final ValueListenable<Set<String>> picked;

  /// Called with the sheet's own context, so a toast shows inside it.
  final void Function(String id, BuildContext context) onToggle;
  final VoidCallback onClear;

  @override
  State<AllAreasSheet> createState() => _AllAreasSheetState();
}

class _AllAreasSheetState extends State<AllAreasSheet> {
  final _query = TextEditingController();

  /// Districts whose areas show; those with a pick start open.
  late final Set<String> _open = {
    for (final g in widget.tree.groups)
      if ([
        g.district,
        ...g.parts,
      ].any((d) => widget.picked.value.contains(d.id)))
        g.district.id,
  };

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _name(District d) => widget.names[d.id]!;

  bool _matches(District d, String query) => [
    _name(d),
    d.nameKa,
    ?d.nameEn,
    latinGeorgian(d.nameKa),
  ].any((n) => n.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
    valueListenable: widget.picked,
    builder: (context, picked, _) => _sheet(context, picked),
  );

  Widget _sheet(BuildContext context, Set<String> picked) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final query = _query.text.trim().toLowerCase();
    final streets = widget.streets;
    final total = widget.names.length;
    String count(District d) {
      final n = streets?[d.id]?.length ?? 0;
      return l10n.areaStreetCount(n, formatNumber(n));
    }

    // A matching district shows all its areas; otherwise only the matches.
    final sections =
        [
          for (final g in widget.tree.groups)
            if (query.isEmpty || _matches(g.district, query))
              (group: g, shown: g.parts)
            else if (g.parts.where((d) => _matches(d, query)).toList()
                case final hits when hits.isNotEmpty)
              (group: g, shown: hits),
        ]..sort(
          (a, b) => _name(a.group.district).compareTo(_name(b.group.district)),
        );

    Widget districtRow(DistrictGroup g) {
      final d = g.district;
      final open = _open.contains(d.id);
      return ListRow(
        title: _name(d),
        subtitle: '${l10n.areaDistrictTag} · ${count(d)}',
        check: picked.contains(d.id)
            ? CheckState.on
            : g.parts.any((p) => picked.contains(p.id))
            ? CheckState.partial
            : CheckState.off,
        trailing: g.parts.isEmpty || query.isNotEmpty
            ? null
            : PindoroIconButton(
                glyph: open
                    ? PindoroGlyph.chevronDown
                    : PindoroGlyph.chevronRight,
                semanticLabel: l10n.areaShowParts(_name(d)),
                onPressed: () => setState(() {
                  if (!_open.remove(d.id)) _open.add(d.id);
                }),
              ),
        onTap: () => widget.onToggle(d.id, context),
      );
    }

    Widget partRow(District district, District d) {
      final included = picked.contains(district.id);
      return Padding(
        padding: const EdgeInsets.only(left: PindoroSpace.s4),
        child: ListRow(
          title: _name(d),
          subtitle: included
              ? '${l10n.areaIncluded(_name(district))} · ${count(d)}'
              : count(d),
          check: included
              ? CheckState.included
              : picked.contains(d.id)
              ? CheckState.on
              : CheckState.off,
          onTap: () => widget.onToggle(d.id, context),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        PindoroSpace.s4,
        PindoroSpace.s4,
        PindoroSpace.s4,
        bottomActionGap(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Text(
            l10n.areaAllTitle,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  areaCountLine(l10n, total, picked, streets),
                  style: PindoroType.labelMd.copyWith(color: c.textSecondary),
                ),
              ),
              if (picked.isNotEmpty)
                PindoroButton(
                  label: l10n.areaClear,
                  variant: PindoroButtonVariant.tertiary,
                  onPressed: widget.onClear,
                ),
            ],
          ),
          if (fewStreets(picked, streets))
            Text(
              l10n.areaFewStreets,
              style: PindoroType.bodySm.copyWith(color: c.warningText),
            ),
          SearchField(
            controller: _query,
            placeholder: l10n.areaSearchHint,
            clearLabel: l10n.cityClearSearch,
            onChanged: (_) => setState(() {}),
          ),
          Expanded(
            child: sections.isEmpty
                ? Text(
                    l10n.areaNoResults(_query.text.trim()),
                    textAlign: TextAlign.center,
                    style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
                  )
                : ListView(
                    children: [
                      for (final (:group, :shown) in sections) ...[
                        districtRow(group),
                        if (query.isNotEmpty ||
                            _open.contains(group.district.id))
                          for (final d
                              in shown.toList()
                                ..sort((a, b) => _name(a).compareTo(_name(b))))
                            partRow(group.district, d),
                      ],
                    ],
                  ),
          ),
          PindoroButton(
            label: picked.isEmpty ? l10n.areaNoneButton : l10n.commonDone,
            onPressed: picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
