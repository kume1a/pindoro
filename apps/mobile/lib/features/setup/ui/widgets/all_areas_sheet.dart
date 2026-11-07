import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

class AllAreasSheet extends StatefulWidget {
  const AllAreasSheet({
    super.key,
    required this.groups,
    required this.names,
    required this.picked,
    required this.onToggle,
  });

  final List<({District district, List<District> parts})> groups;
  final Map<String, String> names;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  @override
  State<AllAreasSheet> createState() => _AllAreasSheetState();
}

class _AllAreasSheetState extends State<AllAreasSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final query = _query.text.trim().toLowerCase();
    bool matches(District d) =>
        widget.names[d.id]!.toLowerCase().contains(query);
    String name(District d) => widget.names[d.id]!;
    final sections = [
      for (final g in widget.groups)
        (
          title: name(g.district),
          areas: [
            g.district,
            ...g.parts..sort((a, b) => name(a).compareTo(name(b))),
          ].where(matches).toList(),
        ),
    ]..sort((a, b) => a.title.compareTo(b.title));
    final shown = sections.where((s) => s.areas.isNotEmpty).toList();
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
          SearchField(
            controller: _query,
            placeholder: l10n.areaSearchHint,
            clearLabel: l10n.cityClearSearch,
            onChanged: (_) => setState(() {}),
          ),
          Expanded(
            child: shown.isEmpty
                ? Text(
                    l10n.areaNoResults(_query.text.trim()),
                    textAlign: TextAlign.center,
                    style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
                  )
                : ListView(
                    children: [
                      for (final s in shown) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            top: PindoroSpace.s3,
                            bottom: PindoroSpace.s2,
                          ),
                          child: SectionTitle(s.title),
                        ),
                        Wrap(
                          spacing: PindoroSpace.s2,
                          runSpacing: PindoroSpace.s2,
                          children: [
                            for (final d in s.areas)
                              PindoroChip(
                                label: name(d),
                                selected: widget.picked.contains(d.id),
                                onPressed: () => widget.onToggle(d.id),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          PindoroButton(
            label: l10n.commonDone,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
