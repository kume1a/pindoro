import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What a screen shows until the chosen city's pack is open: nothing while a
/// local pack opens, the first download's progress, or its failure.
class PackPending extends ConsumerWidget {
  const PackPending({super.key, required this.pack});

  final AsyncValue<PackRepository> pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    if (pack.error != null) {
      return PageScaffold(
        title: '',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            PindoroButton(
              label: l10n.commonChooseCity,
              variant: PindoroButtonVariant.secondary,
              onPressed: () => context.go(Routes.city),
            ),
            PindoroButton(
              label: l10n.commonTryAgain,
              onPressed: () => ref.invalidate(packRepositoryProvider),
            ),
          ],
        ),
        children: [
          const SizedBox(height: PindoroSpace.s8),
          const Pindo(PindoExpression.encouraging, height: 96),
          Text(
            l10n.packFailedTitle,
            textAlign: TextAlign.center,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          Text(
            l10n.packFailedBody,
            textAlign: TextAlign.center,
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
        ],
      );
    }
    final progress = ref.watch(packDownloadProvider);
    if (progress == null) return const Scaffold();
    final locale = Localizations.localeOf(context);
    final city = locale.languageCode == 'ka'
        ? progress.city.nameKa
        : progress.city.nameEn;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(PindoroSpace.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s4,
            children: [
              const Pindo(PindoExpression.thinking, height: 88),
              Text(
                l10n.packDownloading(city),
                textAlign: TextAlign.center,
                style: PindoroType.titleMd.copyWith(color: c.textPrimary),
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}
