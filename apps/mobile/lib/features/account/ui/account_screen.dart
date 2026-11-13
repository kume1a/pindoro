import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/account/data/account_api.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/account/data/backup.dart';
import 'package:pindoro/features/account/ui/widgets/account_widgets.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Sign in, create an account, or set a new password with the recovery code
/// (Forgot password?). Signing in where the account has a backup restores
/// it, asking first when this phone has progress of its own.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  // A phone signed out by another one keeps its username for signing in.
  late final _username = TextEditingController(
    text: ref.read(accountProvider).value?.username,
  );
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _resetting = false;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _tidyUsername => tidyUsername(_username.text);

  bool get _valid =>
      isUsername(_tidyUsername) &&
      isPassword(_password.text) &&
      (!_resetting || isRecoveryCode(tidyRecoveryCode(_code.text)));

  /// Runs [action], then leaves; a failure shows as a toast ([unauthorized]
  /// for a 401).
  Future<void> _run(
    Future<void> Function() action, {
    required String unauthorized,
  }) async {
    if (_busy || !_valid) return;
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        showToast(
          context,
          accountFailure(context.l10n, e, unauthorized: unauthorized),
        );
      }
    } on UnreadableBackup {
      if (mounted) showToast(context, context.l10n.accountRestoreFailed);
    } on SignInGivenUp {
      // Nothing was saved.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server took these credentials: the platform may offer to save them.
  void _accepted() => TextInput.finishAutofillContext();

  Future<void> _create() async {
    final session = await ref
        .read(accountActionsProvider)
        .create(_tidyUsername, _password.text);
    _accepted();
    if (mounted) await showRecoveryCodeDialog(context, session.recoveryCode!);
  }

  Future<void> _signIn() async {
    final session = await ref
        .read(accountActionsProvider)
        .signIn(_tidyUsername, _password.text);
    await _takeOver(session);
  }

  Future<void> _reset() async {
    final session = await ref
        .read(accountActionsProvider)
        .reset(_tidyUsername, tidyRecoveryCode(_code.text), _password.text);
    if (mounted) await showRecoveryCodeDialog(context, session.recoveryCode!);
    await _takeOver(session);
  }

  Future<void> _takeOver(Session session) async {
    _accepted();
    await ref
        .read(accountActionsProvider)
        .takeOver(
          session,
          askRestore: (at) async => mounted ? askRestore(context, at) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    void submit() => unawaited(
      _resetting
          ? _run(_reset, unauthorized: l10n.accountWrongCode)
          : _run(_signIn, unauthorized: l10n.accountWrong),
    );
    return PageScaffold(
      title: _resetting ? l10n.accountReset : l10n.accountTitle,
      children: [
        Text(
          _resetting ? l10n.accountResetIntro : l10n.accountIntro,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              AccountField(AccountFieldKind.username, controller: _username),
              if (_resetting)
                AccountField(AccountFieldKind.recoveryCode, controller: _code),
              AccountField(
                _resetting
                    ? AccountFieldKind.newPassword
                    : AccountFieldKind.password,
                controller: _password,
                last: true,
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
        Text(
          l10n.accountRules,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_username, _password, _code]),
          builder: (context, _) {
            final enabled = !_busy && _valid;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                PindoroButton(
                  label: _resetting ? l10n.accountReset : l10n.accountSignIn,
                  onPressed: enabled ? submit : null,
                ),
                if (!_resetting)
                  PindoroButton(
                    label: l10n.accountCreate,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: enabled
                        ? () => unawaited(
                            _run(_create, unauthorized: l10n.accountWrong),
                          )
                        : null,
                  ),
                PindoroButton(
                  label: _resetting
                      ? l10n.accountBackToSignIn
                      : l10n.accountForgot,
                  variant: PindoroButtonVariant.tertiary,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _resetting = !_resetting),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Settings → Account → Change password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  bool get _valid => _current.text.isNotEmpty && isPassword(_next.text);

  Future<void> _change() async {
    if (_busy || !_valid) return;
    final l10n = context.l10n;
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    try {
      await ref
          .read(accountActionsProvider)
          .changePassword(_current.text, _next.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      showToast(context, l10n.accountPasswordChanged);
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showToast(context, accountFailure(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return PageScaffold(
      title: l10n.accountChangePassword,
      children: [
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              AccountField(
                AccountFieldKind.password,
                controller: _current,
                placeholder: l10n.accountCurrentPassword,
              ),
              AccountField(
                AccountFieldKind.newPassword,
                controller: _next,
                last: true,
                onSubmitted: (_) => unawaited(_change()),
              ),
            ],
          ),
        ),
        Text(
          l10n.accountPasswordRule,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_current, _next]),
          builder: (context, _) => PindoroButton(
            label: l10n.accountChangePassword,
            onPressed: !_busy && _valid ? () => unawaited(_change()) : null,
          ),
        ),
      ],
    );
  }
}
