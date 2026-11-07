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
    required this.title,
    required this.children,
    this.footer,
    this.showBack = true,
    this.trailing,
  });

  final String title;
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
      child: ContentColumn(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            PindoroSpace.s4,
            PindoroSpace.s4,
            PindoroSpace.s4,
            bottomActionGap(context),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Primary actions end 26 dp above the bottom safe area.
double bottomActionGap(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 26;
