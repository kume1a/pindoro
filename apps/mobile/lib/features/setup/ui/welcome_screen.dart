import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/launch_overlay.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/cities.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// First run until a round is finished: Pindo, the wordmark and the way in
/// (choose a city, or play the saved settings).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final recents = ref.watch(recentCityIdsProvider).value ?? const [];
    final area = settings?.area;
    final difficulty = settings?.lastDifficulty;
    // Only a resumable player needs the pack; watching it on first run would
    // download the default city before one is chosen.
    final resumes = recents.isNotEmpty && area != null && difficulty != null
        ? switch (ref.watch(packRepositoryProvider).value) {
            final pack? => resumeLabel(
              context,
              pack,
              area,
              difficulty,
              settings,
            ),
            null => null,
          }
        : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PindoroSpace.s4,
                PindoroSpace.s2,
                PindoroSpace.s4,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PindoroIconButton(
                    glyph: PindoroGlyph.settings,
                    semanticLabel: l10n.a11ySettings,
                    onPressed: () => context.push(Routes.settings),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PindoroSpace.s4),
                  child: Column(
                    spacing: PindoroSpace.s4,
                    children: [
                      const _WavingPindo(),
                      const Wordmark(),
                      Text(
                        l10n.welcomeTagline,
                        textAlign: TextAlign.center,
                        style: PindoroType.bodyLg.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ContentColumn(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  PindoroSpace.s4,
                  0,
                  PindoroSpace.s4,
                  bottomActionGap(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: PindoroSpace.s3,
                  children: [
                    if (recents.isEmpty)
                      LipBox(
                        padding: const EdgeInsets.all(PindoroSpace.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.welcomeEmptyTitle,
                              style: PindoroType.titleMd.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              l10n.welcomeEmptyBody,
                              style: PindoroType.bodySm.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (resumes != null) ...[
                      PindoroButton(
                        label: l10n.welcomeFindCity,
                        icon: PindoroGlyph.search,
                        variant: PindoroButtonVariant.tertiary,
                        onPressed: () => context.push(Routes.city),
                      ),
                      Text(
                        resumes,
                        textAlign: TextAlign.center,
                        style: PindoroType.labelMd.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                    Semantics(
                      label: resumes == null ? null : l10n.a11yPlay(resumes),
                      child: PindoroButton(
                        label: resumes == null
                            ? l10n.commonChooseCity
                            : l10n.commonPlay,
                        icon: resumes == null ? null : PindoroGlyph.play,
                        hero: true,
                        onPressed: () => resumes == null
                            ? context.push(Routes.city)
                            : context.push(Routes.round),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether Pindo already waved in this launch.
bool _waved = false;

/// Pindo waves in once per launch as the launch reveal opens: it pops up
/// and rocks on its tip with `spring.bouncy`. Static after that and with
/// reduce motion.
class _WavingPindo extends StatefulWidget {
  const _WavingPindo();

  @override
  State<_WavingPindo> createState() => _WavingPindoState();
}

class _WavingPindoState extends State<_WavingPindo>
    with SingleTickerProviderStateMixin {
  static const Duration _wave = Duration(milliseconds: 700);
  static const double _tilt = 0.35;
  static const Widget _pindo = Pindo(PindoExpression.happy, height: 104);

  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: launchReveal + _wave,
  );
  final SpringSimulation _spring = SpringSimulation(
    PindoroMotion.springBouncy,
    1,
    0,
    0,
  );
  final bool _plays = !_waved;

  @override
  void initState() {
    super.initState();
    _waved = true;
    if (_plays) _t.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_plays || MediaQuery.disableAnimationsOf(context)) return _pindo;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final elapsed =
            _t.value * _t.duration!.inMilliseconds -
            launchReveal.inMilliseconds;
        final off = elapsed < 0 ? 1.0 : _spring.x(elapsed / 1000);
        return Opacity(
          opacity: (1 - off).clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: -_tilt * off,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scale: 1 - 0.4 * off,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: _pindo,
    );
  }
}
