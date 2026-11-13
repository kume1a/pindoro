import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What a failed league call tells the player: [offline] when the server
/// wasn't reached, else that the league is down for now.
String leagueFailure(AppLocalizations l10n, Object error, String offline) =>
    error is ApiException && error.offline ? offline : l10n.leagueUnavailable;

/// The league name field and its button, enabled once the name fits the
/// rule (pindoro_core `isLeagueName`). A failed [onSubmit] shows [failed]
/// when offline.
class LeagueNameForm extends ConsumerStatefulWidget {
  const LeagueNameForm({
    super.key,
    required this.action,
    required this.failed,
    required this.onSubmit,
    this.initial = '',
  });

  final String action;
  final String failed;
  final String initial;
  final Future<void> Function(String name) onSubmit;

  @override
  ConsumerState<LeagueNameForm> createState() => _LeagueNameFormState();
}

class _LeagueNameFormState extends ConsumerState<LeagueNameForm> {
  late final _name = TextEditingController(text: widget.initial);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _tidy => leagueName(_name.text);

  Future<void> _submit() async {
    if (_busy || !isLeagueName(_tidy)) return;
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_tidy);
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, leagueFailure(context.l10n, e, widget.failed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s3,
      children: [
        SearchField(
          controller: _name,
          placeholder: l10n.leagueNamePlaceholder,
          clearLabel: l10n.leagueNameClear,
          glyph: PindoroGlyph.user,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => unawaited(_submit()),
        ),
        Text(
          l10n.leagueNameRule,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => PindoroButton(
            label: widget.action,
            onPressed: _busy || !isLeagueName(_tidy)
                ? null
                : () => unawaited(_submit()),
          ),
        ),
      ],
    );
  }
}

/// Settings → League → League name.
class LeagueNameScreen extends ConsumerWidget {
  const LeagueNameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = ref.watch(leagueAccountProvider).value;
    return PageScaffold(
      title: l10n.settingsLeagueName,
      children: [
        if (account != null)
          LeagueNameForm(
            initial: account.name,
            action: l10n.leagueSave,
            failed: l10n.leagueSaveFailed,
            onSubmit: (name) async {
              await ref.read(leagueActionsProvider).rename(account, name);
              if (context.mounted) context.pop();
            },
          ),
      ],
    );
  }
}
