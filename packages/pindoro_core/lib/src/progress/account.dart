/// The backup account rules. `apps/api/src/modules/accounts/accounts.rules.ts`
/// holds the same; both pass `shared/fixtures/account_vectors.json`.
abstract final class AccountRules {
  static const int usernameMin = 3;
  static const int usernameMax = 24;

  /// Counted in characters (code points), as the server counts them.
  static const int passwordMin = 8;
  static const int passwordMax = 200;

  /// A recovery code: this many characters of [codeAlphabet] (no 0/o, 1/i/l).
  static const int codeLength = 16;
  static const String codeAlphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
}

/// Usernames ignore case and surrounding spaces.
String tidyUsername(String raw) => raw.trim().toLowerCase();

final _usernameShape = RegExp(r'^[a-z0-9._-]+$');

/// Whether a [tidyUsername] may be used: 3–24 of a–z, 0–9, `.`, `_`, `-`.
bool isUsername(String username) =>
    username.length >= AccountRules.usernameMin &&
    username.length <= AccountRules.usernameMax &&
    _usernameShape.hasMatch(username);

bool isPassword(String password) {
  final length = password.runes.length;
  return length >= AccountRules.passwordMin &&
      length <= AccountRules.passwordMax;
}

/// A typed recovery code without case, spaces or dashes.
String tidyRecoveryCode(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');

bool isRecoveryCode(String code) =>
    code.length == AccountRules.codeLength &&
    code.split('').every(AccountRules.codeAlphabet.contains);

/// The code in dashed groups of four, as the app shows it.
String groupRecoveryCode(String code) => [
  for (var i = 0; i < code.length; i += 4)
    code.substring(i, i + 4 > code.length ? code.length : i + 4),
].join('-');
