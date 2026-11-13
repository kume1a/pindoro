import { randomBytes, scrypt, scryptSync, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { and, eq, type SQL, sql } from "drizzle-orm";
import type { Static } from "typebox";
import type { Db } from "../../db/client.ts";
import { account } from "../../db/schema.ts";
import { hashToken, newToken } from "../../http.ts";
import { newRecoveryCode } from "./accounts.rules.ts";
import type { Session } from "./accounts.schemas.ts";

type SessionNode = Static<typeof Session>;

const scryptAsync = promisify(scrypt) as (
  password: string,
  salt: Buffer,
  length: number,
) => Promise<Buffer>;
const KEY_LENGTH = 32;

const hashPassword = async (password: string): Promise<string> => {
  const salt = randomBytes(16);
  const key = await scryptAsync(password, salt, KEY_LENGTH);
  return `${salt.toString("hex")}:${key.toString("hex")}`;
};

// An unknown username still costs one scrypt, so timing doesn't tell which usernames exist.
const unknownSalt = randomBytes(16);
const UNKNOWN_USER_HASH = `${unknownSalt.toString("hex")}:${scryptSync("", unknownSalt, KEY_LENGTH).toString("hex")}`;

const passwordMatches = async (password: string, stored: string): Promise<boolean> => {
  const [salt = "", key = ""] = stored.split(":");
  const actual = await scryptAsync(password, Buffer.from(salt, "hex"), KEY_LENGTH);
  const expected = Buffer.from(key, "hex");
  return expected.length === KEY_LENGTH && timingSafeEqual(actual, expected);
};

// A sha256 hex never contains ":", so no token can match a signed-out account.
const signedOut = sql<string>`'out:' || ${account.id}`;

const toSession = (
  token: string,
  username: string,
  backupAt: Date | null,
  recoveryCode?: string,
): SessionNode => ({
  token,
  account: { username },
  backupAt: backupAt?.toISOString() ?? null,
  ...(recoveryCode === undefined ? {} : { recoveryCode }),
});

/** The new account's session with its recovery code, or undefined when the username is taken. */
export const createAccount = async (
  db: Db,
  username: string,
  password: string,
): Promise<SessionNode | undefined> => {
  const token = newToken();
  const recoveryCode = newRecoveryCode();
  const [row] = await db
    .insert(account)
    .values({
      username,
      passwordHash: await hashPassword(password),
      tokenHash: hashToken(token),
      recoveryHash: hashToken(recoveryCode),
    })
    .onConflictDoNothing({ target: account.username })
    .returning({ id: account.id });
  return row && toSession(token, username, null, recoveryCode);
};

/**
 * A new token for this phone (the phone holding the old one is signed out), with the backup time
 * read in the same statement, so an upload can't land unseen in between.
 */
const rotate = async (
  db: Db,
  id: string,
  username: string,
  set: Partial<typeof account.$inferInsert> = {},
  recoveryCode?: string,
): Promise<SessionNode> => {
  const token = newToken();
  const [row] = await db
    .update(account)
    .set({ ...set, tokenHash: hashToken(token) })
    .where(eq(account.id, id))
    .returning({ backupAt: account.backupAt });
  return toSession(token, username, row?.backupAt ?? null, recoveryCode);
};

export const signIn = async (
  db: Db,
  username: string,
  password: string,
): Promise<SessionNode | undefined> => {
  const [row] = await db
    .select({ id: account.id, passwordHash: account.passwordHash })
    .from(account)
    .where(eq(account.username, username));
  const matches = await passwordMatches(password, row?.passwordHash ?? UNKNOWN_USER_HASH);
  return row && matches ? rotate(db, row.id, username) : undefined;
};

/** Sets a new password with the recovery code, which is then replaced; undefined when it's wrong. */
export const resetPassword = async (
  db: Db,
  username: string,
  recoveryCode: string,
  password: string,
): Promise<SessionNode | undefined> => {
  const [row] = await db
    .select({ id: account.id })
    .from(account)
    .where(and(eq(account.username, username), eq(account.recoveryHash, hashToken(recoveryCode))));
  if (!row) return undefined;
  const next = newRecoveryCode();
  const set = { passwordHash: await hashPassword(password), recoveryHash: hashToken(next) };
  return rotate(db, row.id, username, set, next);
};

const byToken = (token: string): SQL => eq(account.tokenHash, hashToken(token));

export const isLiveToken = async (db: Db, token: string): Promise<boolean> => {
  const [row] = await db.select({ id: account.id }).from(account).where(byToken(token));
  return row !== undefined;
};

/** "unknown" for a dead token, "wrong" for a wrong current password. */
export const changePassword = async (
  db: Db,
  token: string,
  current: string,
  next: string,
): Promise<"changed" | "unknown" | "wrong"> => {
  const [row] = await db
    .select({ id: account.id, passwordHash: account.passwordHash })
    .from(account)
    .where(byToken(token));
  if (!row) return "unknown";
  if (!(await passwordMatches(current, row.passwordHash))) return "wrong";
  await db
    .update(account)
    .set({ passwordHash: await hashPassword(next) })
    .where(eq(account.id, row.id));
  return "changed";
};

/** False when the token was already dead. */
export const signOut = async (db: Db, token: string): Promise<boolean> => {
  const rows = await db
    .update(account)
    .set({ tokenHash: signedOut })
    .where(byToken(token))
    .returning({ id: account.id });
  return rows.length > 0;
};

/** Deletes the account and its backup; false when the token was already dead. */
export const deleteAccount = async (db: Db, token: string): Promise<boolean> => {
  const rows = await db.delete(account).where(byToken(token)).returning({ id: account.id });
  return rows.length > 0;
};

/** When the backup was saved; undefined when the token died meanwhile (another sign-in). */
export const saveBackup = async (
  db: Db,
  token: string,
  backup: Buffer,
  at: Date,
): Promise<Date | undefined> => {
  const [row] = await db
    .update(account)
    .set({ backup, backupAt: at })
    .where(byToken(token))
    .returning({ backupAt: account.backupAt });
  return row?.backupAt ?? undefined;
};

/** The backup (null before the first), or undefined for a dead token. */
export const backupOf = async (db: Db, token: string): Promise<Buffer | null | undefined> => {
  const [row] = await db.select({ backup: account.backup }).from(account).where(byToken(token));
  return row?.backup;
};
