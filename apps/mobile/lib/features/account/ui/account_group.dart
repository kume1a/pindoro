import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/account/ui/widgets/account_widgets.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Settings → Account. Without an account, a way in; signed out by another
/// phone, a way back in; signed in, the last backup (a tap backs up now),
/// Change password, Sign out and Delete account.
class AccountGroup extends ConsumerWidget {
  const AccountGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = ref.watch(accountProvider).value;
    ListRow link(
      String title,
      String? subtitle,
      PindoroGlyph glyph,
      String to,
    ) => ListRow(
      title: title,
      subtitle: subtitle,
      leading: RowTile(glyph),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () {
        ref.read(feedbackProvider).tap();
        unawaited(context.push(to));
      },
    );
    return ListGroup(
      children: switch (account) {
        null => [
          link(
            l10n.accountBackUp,
            l10n.accountBackUpSubtitle,
            PindoroGlyph.user,
            Routes.account,
          ),
        ],
        Account(token: null) => [
          link(
            l10n.accountSignedOutHere,
            l10n.accountSignedOutHereSubtitle,
            PindoroGlyph.user,
            Routes.account,
          ),
        ],
        final Account signedIn => [
          ListRow(
            title: l10n.accountSignedIn(signedIn.username),
            subtitle: switch (signedIn.backedUpAt) {
              final at? => l10n.accountBackedUp(formatSince(at, l10n)),
              null => l10n.accountNotBackedUp,
            },
            leading: const RowTile(PindoroGlyph.user),
            onTap: () => unawaited(_backUpNow(context, ref)),
          ),
          link(
            l10n.accountChangePassword,
            null,
            PindoroGlyph.lock,
            Routes.accountPassword,
          ),
          ListRow(
            title: l10n.accountSignOut,
            subtitle: l10n.accountSignOutSubtitle,
            leading: const RowTile(PindoroGlyph.back),
            onTap: () => unawaited(_signOut(context, ref)),
          ),
          ListRow(
            title: l10n.accountDelete,
            subtitle: l10n.accountDeleteSubtitle,
            leading: const RowTile(PindoroGlyph.close),
            onTap: () => unawaited(_delete(context, ref)),
          ),
        ],
      },
    );
  }

  Future<void> _backUpNow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    ref.read(feedbackProvider).tap();
    String done;
    try {
      await ref.read(backupSyncProvider).backUp();
      done = l10n.accountBackedUpNow;
    } on ApiException catch (e) {
      done = accountFailure(l10n, e);
    } on Object {
      done = l10n.accountBackUpFailed;
    }
    if (context.mounted) showToast(context, done);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    ref.read(feedbackProvider).tap();
    final signOut = await showFixedDialog(
      context,
      title: l10n.accountSignOutTitle,
      body: l10n.accountSignOutBody,
      primary: l10n.accountSignOutStay,
      secondary: l10n.accountSignOut,
    );
    if (signOut && context.mounted) {
      await _act(context, ref.read(accountActionsProvider).signOut);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    ref.read(feedbackProvider).tap();
    final delete = await showFixedDialog(
      context,
      title: l10n.accountDeleteTitle,
      body: l10n.accountDeleteBody,
      primary: l10n.accountDeleteKeep,
      secondary: l10n.accountDeleteConfirm,
    );
    if (delete && context.mounted) {
      await _act(context, ref.read(accountActionsProvider).delete);
    }
  }

  Future<void> _act(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, accountFailure(context.l10n, e));
    }
  }
}
