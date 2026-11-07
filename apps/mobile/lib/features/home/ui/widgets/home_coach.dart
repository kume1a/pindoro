import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The first Home's coach mark (canvas M-13), hanging under [child] while
/// [show]. Any tap closes it.
class HomeCoach extends StatefulWidget {
  const HomeCoach({
    super.key,
    required this.show,
    required this.onClose,
    required this.child,
  });

  final bool show;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<HomeCoach> createState() => _CoachState();
}

class _CoachState extends State<HomeCoach> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    // The overlay can't change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(HomeCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show != oldWidget.show) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  void _sync() {
    if (!mounted) return;
    widget.show ? _portal.show() : _portal.hide();
  }

  void _close() {
    _portal.hide();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Semantics(
          button: true,
          label: l10n.homeCoachTitle,
          hint: l10n.homeCoachBody,
          onTap: _close,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _link,
                  targetAnchor: Alignment.bottomLeft,
                  offset: const Offset(-PindoroSpace.s2, PindoroSpace.s2),
                  child: CoachBubble(
                    title: l10n.homeCoachTitle,
                    body: l10n.homeCoachBody,
                    pointsUp: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
