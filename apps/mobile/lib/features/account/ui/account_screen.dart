import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/account/data/backup.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What a failed account call tells the player.
String accountFailure(AppLocalizations l10n, ApiException error) =>
    switch (error.status) {
      null => l10n.accountOffline,
      401 => l10n.accountWrong,
      409 => l10n.accountTaken,
      _ => l10n.accountUnavailable,
    };

/// Settings → Account: a way in while signed out; signed in, the last backup,
/// and a tap backs up now.
class AccountGroup extends ConsumerWidget {
  const AccountGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final feedback = ref.read(feedbackProvider);
    final signedIn = ref.watch(accountProvider).value;
    return ListGroup(
      children: [
        if (signedIn == null)
          ListRow(
            title: l10n.accountBackUp,
            subtitle: l10n.accountBackUpSubtitle,
            leading: const RowTile(PindoroGlyph.user),
            trailing: const PindoroIcon(PindoroGlyph.chevronRight),
            onTap: () {
              feedback.tap();
              unawaited(context.push(Routes.account));
            },
          )
        else
          ListRow(
            title: l10n.accountSignedIn(signedIn.username),
            subtitle: switch (signedIn.backedUpAt) {
              final at? => l10n.accountBackedUp(
                formatAgo(DateTime.now().difference(at), l10n),
              ),
              null => l10n.accountNotBackedUp,
            },
            leading: const RowTile(PindoroGlyph.user),
            onTap: () => unawaited(_backUpNow(context, ref)),
          ),
      ],
    );
  }

  Future<void> _backUpNow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    ref.read(feedbackProvider).tap();
    try {
      await ref.read(backupSyncProvider).backUp();
      if (context.mounted) showToast(context, l10n.accountBackedUpNow);
    } on ApiException catch (e) {
      if (context.mounted) {
        showToast(
          context,
          e.unknownToken ? l10n.accountSignedOut : accountFailure(l10n, e),
        );
      }
    }
  }
}

/// Create an account or sign in. Signing in where the account has a backup
/// restores it, asking first when this phone has progress of its own.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid =>
      isUsername(tidyUsername(_username.text)) && isPassword(_password.text);

  Future<void> _run(
    Future<void> Function(String username, String password) action,
  ) async {
    if (_busy || !_valid) return;
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    try {
      await action(tidyUsername(_username.text), _password.text);
    } on ApiException catch (e) {
      if (mounted) showToast(context, accountFailure(context.l10n, e));
    } on UnreadableBackup {
      if (mounted) showToast(context, context.l10n.accountRestoreFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(String username, String password) async {
    await ref.read(accountActionsProvider).create(username, password);
    if (mounted) context.pop();
  }

  Future<void> _signIn(String username, String password) async {
    final actions = ref.read(accountActionsProvider);
    final session = await actions.signIn(username, password);
    if (session.backupAt case final at?) {
      final restore = await actions.hasProgress()
          ? await _askRestore(at)
          : true;
      if (restore == null) return;
      if (restore) return actions.restore(session);
    }
    await actions.keep(session);
    if (mounted) context.pop();
  }

  /// Restore (true) or keep this phone's progress (false); null when closed.
  Future<bool?> _askRestore(DateTime backupAt) async {
    if (!mounted) return null;
    final l10n = context.l10n;
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.accountRestoreTitle,
        body: l10n.accountRestoreBody(
          formatAgo(DateTime.now().difference(backupAt), l10n),
        ),
        primary: l10n.accountRestore,
        secondary: l10n.accountKeep,
      ),
    );
    return keep == null ? null : !keep;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return PageScaffold(
      title: l10n.accountTitle,
      children: [
        Text(
          l10n.accountIntro,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              SearchField(
                controller: _username,
                placeholder: l10n.accountUsername,
                clearLabel: l10n.accountUsernameClear,
                glyph: PindoroGlyph.user,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              SearchField(
                controller: _password,
                placeholder: l10n.accountPassword,
                clearLabel: l10n.accountPasswordClear,
                glyph: PindoroGlyph.lock,
                textInputAction: TextInputAction.done,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => unawaited(_run(_signIn)),
              ),
            ],
          ),
        ),
        Text(
          l10n.accountRules,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_username, _password]),
          builder: (context, _) {
            final enabled = !_busy && _valid;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                PindoroButton(
                  label: l10n.accountSignIn,
                  onPressed: enabled ? () => unawaited(_run(_signIn)) : null,
                ),
                PindoroButton(
                  label: l10n.accountCreate,
                  variant: PindoroButtonVariant.secondary,
                  onPressed: enabled ? () => unawaited(_run(_create)) : null,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
