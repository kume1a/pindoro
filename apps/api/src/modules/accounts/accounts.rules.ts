import { randomInt } from "node:crypto";

// The backup account rules. pindoro_core `progress/account.dart` holds the same; both pass
// shared/fixtures/account_vectors.json.

export const ACCOUNT = {
  usernameMin: 3,
  usernameMax: 24,
  /** Counted in characters (code points), as the app counts them. */
  passwordMin: 8,
  passwordMax: 200,
  /** A recovery code: this many characters of `codeAlphabet` (no 0/o, 1/i/l). */
  codeLength: 16,
  codeAlphabet: "abcdefghjkmnpqrstuvwxyz23456789",
} as const;

/** Usernames ignore case and surrounding spaces. */
export const tidyUsername = (raw: string): string => raw.trim().toLowerCase();

const usernameShape = /^[a-z0-9._-]+$/;

/** Whether a `tidyUsername` may be used: 3–24 of a–z, 0–9, `.`, `_`, `-`. */
export const isUsername = (username: string): boolean =>
  username.length >= ACCOUNT.usernameMin &&
  username.length <= ACCOUNT.usernameMax &&
  usernameShape.test(username);

export const isPassword = (password: string): boolean => {
  const length = [...password].length;
  return length >= ACCOUNT.passwordMin && length <= ACCOUNT.passwordMax;
};

/** A typed recovery code without case, spaces or dashes. */
export const tidyRecoveryCode = (raw: string): string => raw.toLowerCase().replace(/[\s-]/g, "");

export const isRecoveryCode = (code: string): boolean =>
  code.length === ACCOUNT.codeLength && [...code].every((c) => ACCOUNT.codeAlphabet.includes(c));

export const newRecoveryCode = (): string =>
  Array.from(
    { length: ACCOUNT.codeLength },
    () => ACCOUNT.codeAlphabet[randomInt(ACCOUNT.codeAlphabet.length)],
  ).join("");
