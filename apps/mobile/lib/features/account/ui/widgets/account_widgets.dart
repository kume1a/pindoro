import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What a failed account call tells the player; [unauthorized] replaces the
/// signed-out message where a 401 means wrong credentials.
String accountFailure(
  AppLocalizations l10n,
  ApiException error, {
  String? unauthorized,
}) => switch (error.status) {
  null => l10n.accountOffline,
  401 => unauthorized ?? l10n.accountSignedOut,
  403 => l10n.accountWrongPassword,
  409 => l10n.accountTaken,
  429 => l10n.accountTooManyTries,
  _ => l10n.accountUnavailable,
};

enum AccountFieldKind { username, password, newPassword, recoveryCode }

/// A username, password or recovery-code field: no autocorrect, passwords
/// hidden, each with its autofill hint.
class AccountField extends StatelessWidget {
  const AccountField(
    this.kind, {
    super.key,
    required this.controller,
    this.placeholder,
    this.last = false,
    this.onSubmitted,
  });

  final AccountFieldKind kind;
  final TextEditingController controller;

  /// Overrides the kind's own placeholder (Current password).
  final String? placeholder;

  /// The form's last field: Done instead of Next.
  final bool last;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, clear, glyph, hint) = switch (kind) {
      AccountFieldKind.username => (
        l10n.accountUsername,
        l10n.accountUsernameClear,
        PindoroGlyph.user,
        AutofillHints.username,
      ),
      AccountFieldKind.password => (
        l10n.accountPassword,
        l10n.accountPasswordClear,
        PindoroGlyph.lock,
        AutofillHints.password,
      ),
      AccountFieldKind.newPassword => (
        l10n.accountNewPassword,
        l10n.accountPasswordClear,
        PindoroGlyph.lock,
        AutofillHints.newPassword,
      ),
      AccountFieldKind.recoveryCode => (
        l10n.accountRecoveryCode,
        l10n.accountRecoveryCodeClear,
        PindoroGlyph.edit,
        AutofillHints.oneTimeCode,
      ),
    };
    final secret =
        kind == AccountFieldKind.password ||
        kind == AccountFieldKind.newPassword;
    return SearchField(
      controller: controller,
      placeholder: placeholder ?? label,
      clearLabel: clear,
      glyph: glyph,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      obscureText: secret,
      autocorrect: false,
      autofillHints: [hint],
      onSubmitted: onSubmitted,
    );
  }
}

/// A [PindoroDialog] that only its buttons close: false for [primary], true
/// for [secondary].
Future<bool> showFixedDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String primary,
  required String secondary,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: PindoroDialog(
          title: title,
          body: body,
          primary: primary,
          secondary: secondary,
        ),
      ),
    ) ??
    false;

/// Shows a new recovery code once; Copy code puts it on the clipboard.
Future<void> showRecoveryCodeDialog(BuildContext context, String code) async {
  final l10n = context.l10n;
  final copy = !await showFixedDialog(
    context,
    title: l10n.accountCodeTitle,
    body: l10n.accountCodeBody(groupRecoveryCode(code)),
    primary: l10n.accountCodeCopy,
    secondary: l10n.accountCodeDone,
  );
  if (!copy) return;
  await Clipboard.setData(ClipboardData(text: groupRecoveryCode(code)));
  if (context.mounted) showToast(context, l10n.accountCodeCopied);
}

/// Asks whether a backup made at [backupAt] replaces this phone's progress.
Future<bool> askRestore(BuildContext context, DateTime backupAt) {
  final l10n = context.l10n;
  return showFixedDialog(
    context,
    title: l10n.accountRestoreTitle,
    body: l10n.accountRestoreBody(formatSince(backupAt, l10n)),
    primary: l10n.accountRestore,
    secondary: l10n.accountKeep,
  ).then((keep) => !keep);
}
