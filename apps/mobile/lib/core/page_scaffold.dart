import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A non-map screen: top row with back and a `headline.sm` title, content in
/// a centred column (max 600 dp) with 16 dp gutters, and an optional footer
/// pinned in the thumb zone above a 2 dp rule.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    this.title,
    required this.children,
    this.footer,
    this.showBack = true,
    this.trailing,
  });

  /// Null for a page whose first child is its heading (no title row).
  final String? title;
  final List<Widget> children;
  final Widget? footer;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: footer == null,
        child: Column(
          children: [
            if (title case final title?)
              ContentColumn(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PindoroSpace.s4,
                    PindoroSpace.s2,
                    PindoroSpace.s4,
                    0,
                  ),
                  child: Row(
                    spacing: PindoroSpace.s3,
                    children: [
                      if (showBack && context.canPop())
                        PindoroIconButton(
                          glyph: PindoroGlyph.back,
                          semanticLabel: l10n.commonBack,
                          onPressed: context.pop,
                        ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: PindoroType.headlineSm.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                children: [
                  for (final child in children)
                    ContentColumn(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: PindoroSpace.s4),
                        child: child,
                      ),
                    ),
                ],
              ),
            ),
            if (footer != null) PinnedFooter(child: footer!),
          ],
        ),
      ),
    );
  }
}

/// Full width up to 600 dp, centred on tablets.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Actions pinned at the bottom above a 2 dp rule, ending 26 dp above the
/// bottom safe area (v1-screens.md § Frames).
class PinnedFooter extends StatelessWidget {
  const PinnedFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceBase,
        border: Border(
          top: BorderSide(color: c.lineBase, width: PindoroStroke.base),
        ),
      ),
      child: _BottomContent(child),
    );
  }
}

/// [child] in the content column, ending 26 dp above the bottom safe area.
class _BottomContent extends StatelessWidget {
  const _BottomContent(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => ContentColumn(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        PindoroSpace.s4,
        PindoroSpace.s4,
        PindoroSpace.s4,
        bottomActionGap(context),
      ),
      child: child,
    ),
  );
}

/// A sheet docked under a map (`color.surface.overlay`, top `radius.2xl`),
/// its content ending 26 dp above the bottom safe area. It hugs its content
/// in any slot, a Scaffold's bottom bar included.
class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceOverlay,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(PindoroRadius.r2xl),
        ),
        border: Border(
          top: BorderSide(color: c.lineBase, width: PindoroStroke.base),
        ),
      ),
      // ContentColumn centres, so alone it would fill a bounded height.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_BottomContent(child)],
      ),
    );
  }
}

/// Primary actions end 26 dp above the bottom safe area; on a tab, 12 dp
/// above the bottom navigation (canvas R4-14).
double bottomActionGap(BuildContext context) =>
    StatefulNavigationShell.maybeOf(context) == null
    ? MediaQuery.paddingOf(context).bottom + 26
    : PindoroSpace.s3;
