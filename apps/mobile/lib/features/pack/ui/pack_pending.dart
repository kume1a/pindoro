import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What a screen shows until the chosen city's pack is open: a panel at the
/// bottom with the first download's progress or its failure, nothing while a
/// local pack opens. Offline, Tbilisi offers the bundled Vake pack.
class PackPending extends ConsumerWidget {
  const PackPending({super.key, required this.pack});

  final AsyncValue<PackRepository> pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(packRepositoryProvider, (_, next) {
      if (next is AsyncError) ref.read(feedbackProvider).error();
    });
    final c = PindoroTheme.of(context).colors;
    final content = _content(context, ref);
    return Scaffold(
      backgroundColor: c.surfaceSunken,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(PindoroSpace.s4),
                  child: context.canPop()
                      ? MapControl(
                          glyph: PindoroGlyph.back,
                          semanticLabel: context.l10n.commonBack,
                          onPressed: context.pop,
                        )
                      : null,
                ),
              ),
            ),
          ),
          if (content != null) BottomPanel(child: content),
        ],
      ),
    );
  }

  Widget? _content(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    Widget title(String text) =>
        Text(text, style: PindoroType.titleLg.copyWith(color: c.textPrimary));
    Widget body(String text) =>
        Text(text, style: PindoroType.bodyMd.copyWith(color: c.textSecondary));
    Widget column(List<Widget> children) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s3,
      children: children,
    );

    if (pack.error case final error?) {
      final noSpace = error is PackUnavailable && error.noSpace;
      final vake = error is PackUnavailable && error.city == AppConfig.cityId;
      return Semantics(
        liveRegion: true,
        child: column([
          title(noSpace ? l10n.packNoSpaceTitle : l10n.packFailedTitle),
          body(noSpace ? l10n.packNoSpaceBody : l10n.packFailedBody),
          if (vake) body(l10n.packVakeOffline),
          PindoroButton(
            label: vake ? l10n.packPlayVake : l10n.packChooseCity,
            variant: PindoroButtonVariant.secondary,
            onPressed: vake
                ? () => ref.read(offlineVakeProvider.notifier).set(true)
                : () => context.go(Routes.city),
          ),
          PindoroButton(
            label: l10n.commonTryAgain,
            icon: PindoroGlyph.retry,
            onPressed: () => ref.invalidate(packRepositoryProvider),
          ),
        ]),
      );
    }
    final progress = ref.watch(packDownloadProvider);
    if (progress == null) return null;
    final locale = Localizations.localeOf(context);
    final city = locale.languageCode == 'ka'
        ? progress.city.nameKa
        : progress.city.nameEn;
    return column([
      title(l10n.packGettingReady(city)),
      body(l10n.packDownloadBody),
      Semantics(
        value: '${(100 * progress.received / progress.total).round()}%',
        child: Minibar(value: progress.received / progress.total),
      ),
      Text(
        l10n.packDownloadSize(
          formatMegabytes(progress.received, locale),
          formatMegabytes(progress.total, locale),
        ),
        style: PindoroType.labelMd.copyWith(color: c.textSecondary),
      ),
    ]);
  }
}
