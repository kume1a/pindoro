import { Type } from "typebox";

/** Usernames are trimmed and lowercased first, so sign-in ignores case. */
export const USERNAME = /^[a-z0-9._-]{3,24}$/;

// The username is checked with USERNAME after tidying; this only bounds the input.
export const Credentials = Type.Object({
  username: Type.String({ maxLength: 100 }),
  password: Type.String({ minLength: 8, maxLength: 200 }),
});

/** A signed-in phone: its token, and when the account last backed up (null: never). */
export const Session = Type.Object({
  token: Type.String(),
  account: Type.Object({ username: Type.String() }),
  backupAt: Type.Union([Type.String({ format: "date-time" }), Type.Null()]),
});

export const BackupAt = Type.Object({ backupAt: Type.String({ format: "date-time" }) });

/** The app's SQLite file, gzipped. */
export const Backup = Type.Unsafe<Buffer>({ type: "string", format: "binary" });
