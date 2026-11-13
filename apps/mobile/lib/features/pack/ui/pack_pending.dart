import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/widgets/city_scene.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

enum _Phase { connecting, downloading, done, failed }

/// What a screen shows until the chosen city's pack is open: a little city
/// building up as the pack downloads, over a panel with the progress or the
/// failure. A first load waits 300 ms, so a local pack opens without it; Try
/// again keeps the panel and shows the new attempt at once. Offline, Tbilisi
/// offers the bundled Vake pack.
class PackPending extends ConsumerStatefulWidget {
  const PackPending({super.key, required this.pack});

  final AsyncValue<PackRepository> pack;

  @override
  ConsumerState<PackPending> createState() => _PackPendingState();
}

bool _failed(AsyncValue<PackRepository> pack) =>
    pack.hasError && !pack.isLoading;

bool _complete(PackProgress? p) => p != null && p.received >= p.total;

class _PackPendingState extends ConsumerState<PackPending> {
  bool _waited = false;
  late final Timer _wait;

  /// Failures seen here; Try again shakes from the second on.
  late int _failures = _failed(widget.pack) ? 1 : 0;

  /// The last progress, kept while the downloaded pack unpacks and opens.
  PackProgress? _progress;

  @override
  void initState() {
    super.initState();
    _wait = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _waited = true);
    });
  }

  @override
  void didUpdateWidget(PackPending old) {
    super.didUpdateWidget(old);
    if (_failed(widget.pack) && !_failed(old.pack)) _failures++;
  }

  @override
  void dispose() {
    _wait.cancel();
    super.dispose();
  }

  /// Sounds only from the PackPending in view (tabs keep hidden ones mounted).
  void _cue(void Function(GameFeedback feedback) play) {
    if (TickerMode.getValuesNotifier(context).value.enabled) {
      play(ref.read(feedbackProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A Try again reloads as an AsyncError too; only a settled failure buzzes.
    ref.listen(packRepositoryProvider, (_, next) {
      if (next case AsyncError(isLoading: false)) _cue((f) => f.error());
    });
    ref.listen(packDownloadProvider, (previous, next) {
      if (_complete(next) && !_complete(previous)) _cue((f) => f.unlock());
    });
    final pack = widget.pack;
    final live = ref.watch(packDownloadProvider);
    _progress = live ?? (pack.isLoading && !pack.hasError ? _progress : null);
    final progress = _progress;
    final phase = switch (progress) {
      _ when _failed(pack) => _Phase.failed,
      final p? => _complete(p) ? _Phase.done : _Phase.downloading,
      _ when pack.isLoading && (pack.hasError || _waited) => _Phase.connecting,
      _ => null,
    };

    final c = PindoroTheme.of(context).colors;
    final calm = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: c.primarySoft,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: phase == null ? 0 : 1,
                      duration: calm ? calmFade : PindoroMotion.durationBase,
                      child: Padding(
                        padding: const EdgeInsets.all(PindoroSpace.s4),
                        child: ContentColumn(
                          child: CityScene(
                            progress: progress == null
                                ? null
                                : progress.received / progress.total,
                            pindo: switch (phase) {
                              _Phase.done => PindoExpression.cheering,
                              _Phase.failed => PindoExpression.encouraging,
                              _ => PindoExpression.thinking,
                            },
                            moving:
                                phase == _Phase.connecting ||
                                phase == _Phase.downloading,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (context.canPop())
                    Padding(
                      padding: const EdgeInsets.all(PindoroSpace.s4),
                      child: MapControl(
                        glyph: PindoroGlyph.back,
                        semanticLabel: context.l10n.commonBack,
                        onPressed: context.pop,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (phase != null)
            RiseIn(
              distance: PindoroSpace.s2,
              child: BottomPanel(
                child: AnimatedSize(
                  duration: calm ? Duration.zero : PindoroMotion.durationBase,
                  curve: PindoroMotion.easeStandard,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: calm ? calmFade : PindoroMotion.durationFast,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      // Done only relabels the download, so it keeps its bar.
                      key: ValueKey(
                        phase == _Phase.done ? _Phase.downloading : phase,
                      ),
                      child: _panel(phase, progress),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel(_Phase phase, PackProgress? progress) {
    final l10n = context.l10n;
    return switch (phase) {
      _Phase.failed => _Failure(error: widget.pack.error, shake: _failures > 1),
      _Phase.connecting => _PanelText(
        live: true,
        title: l10n.packGettingReadyAny,
        body: l10n.packDownloadBody,
        footer: [
          Row(
            spacing: PindoroSpace.s3,
            children: [const LaneLoader(), _Label(l10n.packConnecting)],
          ),
        ],
      ),
      _Phase.downloading || _Phase.done => _Download(progress: progress!),
    };
  }
}

/// A panel's title, body line and what goes under them.
class _PanelText extends StatelessWidget {
  const _PanelText({
    required this.title,
    required this.body,
    required this.footer,
    this.extra,
    this.live = false,
  });

  final String title;
  final String body;
  final String? extra;
  final List<Widget> footer;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    Widget line(String text) =>
        Text(text, style: PindoroType.bodyMd.copyWith(color: c.textSecondary));
    return Semantics(
      liveRegion: live,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Text(
            title,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          line(body),
          if (extra case final extra?) line(extra),
          ...footer,
        ],
      ),
    );
  }
}

/// A secondary `label.md` line.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: PindoroType.labelMd.copyWith(
      color: PindoroTheme.of(context).colors.textSecondary,
    ),
  );
}

/// The download under way: a bar gliding with the bytes, "0.4 MB of 1.1 MB"
/// and the percent; once all bytes are in, "Unpacking the streets…".
class _Download extends StatelessWidget {
  const _Download({required this.progress});

  final PackProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final share = progress.total == 0
        ? 0.0
        : progress.received / progress.total;
    final percent = l10n.lessonPercent(formatNumber((100 * share).round()));
    final city = context.localName(
      ka: progress.city.nameKa,
      en: progress.city.nameEn,
    );
    return _PanelText(
      title: l10n.packGettingReady(city),
      body: l10n.packDownloadBody,
      footer: [
        Semantics(
          value: percent,
          child: Minibar(value: share, from: 0),
        ),
        Row(
          children: [
            Expanded(
              child: _Label(
                _complete(progress)
                    ? l10n.packUnpacking
                    : l10n.packDownloadSize(
                        formatMegabytes(progress.received, l10n),
                        formatMegabytes(progress.total, l10n),
                      ),
              ),
            ),
            _Label(percent),
          ],
        ),
      ],
    );
  }
}

/// Why the city didn't download and the ways on: Try again (unless only an
/// app update helps) and, offline in Tbilisi, the bundled Vake pack, else
/// another city. [shake] jolts Try again for a repeated failure.
class _Failure extends ConsumerWidget {
  const _Failure({required this.error, required this.shake});

  final Object? error;
  final bool shake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unavailable = switch (error) {
      final PackUnavailable u => u,
      _ => null,
    };
    final reason = unavailable?.reason ?? PackFailure.unreachable;
    final vake = unavailable?.city == AppConfig.defaultCityId;
    final retry = PindoroButton(
      label: l10n.commonTryAgain,
      icon: PindoroGlyph.retry,
      onPressed: () => ref.invalidate(packRepositoryProvider),
    );
    return _PanelText(
      live: true,
      title: switch (reason) {
        PackFailure.needsUpdate => l10n.packUpdateTitle,
        PackFailure.noSpace => l10n.packNoSpaceTitle,
        PackFailure.unreachable || PackFailure.server => l10n.packFailedTitle,
      },
      body: switch (reason) {
        PackFailure.needsUpdate => l10n.packUpdateBody,
        PackFailure.noSpace => l10n.packNoSpaceBody,
        PackFailure.server => l10n.packServerBody,
        PackFailure.unreachable => l10n.packFailedBody,
      },
      extra: vake ? l10n.packVakeOffline : null,
      footer: [
        PindoroButton(
          label: vake ? l10n.packPlayVake : l10n.packChooseCity,
          variant: PindoroButtonVariant.secondary,
          onPressed: vake
              ? () => ref.read(offlineVakeProvider.notifier).set(true)
              : () => context.go(Routes.city),
        ),
        // Trying again can't help until the app is updated.
        if (reason != PackFailure.needsUpdate)
          shake ? Shake(child: retry) : retry,
      ],
    );
  }
}
