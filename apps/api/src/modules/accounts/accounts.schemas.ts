import { Type } from "typebox";

// Usernames, passwords and codes are checked with accounts.rules.ts; these only bound the input.
const Text = Type.String({ maxLength: 1000 });

export const Credentials = Type.Object({ username: Text, password: Text });

export const Reset = Type.Object({ username: Text, recoveryCode: Text, password: Text });

export const PasswordChange = Type.Object({ password: Text, newPassword: Text });

/**
 * A signed-in phone: its token, and when the account last backed up (null: never). A new account
 * and a reset also carry the recovery code, shown once.
 */
export const Session = Type.Object({
  token: Type.String(),
  account: Type.Object({ username: Type.String() }),
  backupAt: Type.Union([Type.String({ format: "date-time" }), Type.Null()]),
  recoveryCode: Type.Optional(Type.String()),
});

export const BackupAt = Type.Object({ backupAt: Type.String({ format: "date-time" }) });

/** The app's SQLite file, gzipped. */
export const Backup = Type.Unsafe<Buffer>({ type: "string", format: "binary" });
