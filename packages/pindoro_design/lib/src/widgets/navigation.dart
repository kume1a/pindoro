import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'tappable.dart';

/// A bottom-nav destination. [badge] counts what waits there (hidden at 0 or
/// null); [semanticLabel] replaces [label] for screen readers.
typedef PindoroNavItem = ({
  PindoroGlyph glyph,
  String label,
  int? badge,
  String? semanticLabel,
});

/// The bottom navigation (`.pd-nav`): `color.surface.raised` under a 2 dp
/// `color.line.base` rule; each item a 56 × 34 icon pill 10 dp from the top
/// (`color.tab.active.bg` on [current]) over its `label.md` label, 3 dp
/// apart. The labels stay above the bottom inset, at least 8 dp under them:
/// the canvas lets them dip into the iPhone's 34 dp inset (84 dp in all),
/// but Android's gesture handle and 3-button bar sit right there.
class PindoroNavBar extends StatelessWidget {
  const PindoroNavBar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
  });

  final List<PindoroNavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final inset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(
          top: BorderSide(color: c.lineBase, width: PindoroStroke.base),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: 10,
          bottom: math.max(inset, PindoroSpace.s2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in items.indexed)
              Expanded(
                child: _NavItem(
                  item,
                  selected: i == current,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.item, {required this.selected, required this.onTap});

  final PindoroNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final ink = selected ? c.tabActiveIcon : c.tabInactiveIcon;
    final pill = selected ? c.tabActiveBg : c.surfaceRaised;
    final badge = item.badge ?? 0;
    return Tappable(
      onTap: onTap,
      selected: selected,
      label: item.semanticLabel ?? item.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pill,
                  borderRadius: BorderRadius.circular(PindoroRadius.md),
                ),
                child: PindoroIcon(item.glyph, color: ink, cut: pill),
              ),
              if (badge > 0)
                PositionedDirectional(top: -6, end: -6, child: _Badge(badge)),
            ],
          ),
          Text(
            item.label,
            textAlign: TextAlign.center,
            style: PindoroType.labelMd.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// The due count: an 18 dp cobalt pill with a 2 dp `color.surface.raised`
/// ring that lifts it off the icon pill.
class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  static const double _size = 18 + 2 * PindoroStroke.base;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      constraints: const BoxConstraints(minWidth: _size, minHeight: _size),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.primaryBase,
        borderRadius: BorderRadius.circular(PindoroRadius.full),
        border: Border.all(color: c.surfaceRaised, width: PindoroStroke.base),
      ),
      child: Text(
        '$count',
        style: PindoroType.labelSm.copyWith(color: c.primaryOn),
      ),
    );
  }
}
