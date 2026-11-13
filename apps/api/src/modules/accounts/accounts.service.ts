import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { eq } from "drizzle-orm";
import type { Static } from "typebox";
import type { Db } from "../../db/client.ts";
import { account } from "../../db/schema.ts";
import { hashToken, newToken } from "../../http.ts";
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

const passwordMatches = async (password: string, stored: string): Promise<boolean> => {
  const [salt = "", key = ""] = stored.split(":");
  const actual = await scryptAsync(password, Buffer.from(salt, "hex"), KEY_LENGTH);
  const expected = Buffer.from(key, "hex");
  return expected.length === KEY_LENGTH && timingSafeEqual(actual, expected);
};

/** The new account's session, or undefined when the username is taken. */
export const createAccount = async (
  db: Db,
  username: string,
  password: string,
): Promise<SessionNode | undefined> => {
  const token = newToken();
  const [row] = await db
    .insert(account)
    .values({ username, passwordHash: await hashPassword(password), tokenHash: hashToken(token) })
    .onConflictDoNothing({ target: account.username })
    .returning({ username: account.username });
  return row && { token, account: row, backupAt: null };
};

/** A new token for this phone, which signs out the phone that had the old one. */
export const signIn = async (
  db: Db,
  username: string,
  password: string,
): Promise<SessionNode | undefined> => {
  const [row] = await db
    .select({ id: account.id, passwordHash: account.passwordHash, backupAt: account.backupAt })
    .from(account)
    .where(eq(account.username, username));
  if (!row || !(await passwordMatches(password, row.passwordHash))) return undefined;
  const token = newToken();
  await db
    .update(account)
    .set({ tokenHash: hashToken(token) })
    .where(eq(account.id, row.id));
  return { token, account: { username }, backupAt: row.backupAt?.toISOString() ?? null };
};

export const accountIdByToken = async (db: Db, token: string): Promise<string | undefined> => {
  const [row] = await db
    .select({ id: account.id })
    .from(account)
    .where(eq(account.tokenHash, hashToken(token)));
  return row?.id;
};

export const saveBackup = async (db: Db, id: string, backup: Buffer, at: Date): Promise<void> => {
  await db.update(account).set({ backup, backupAt: at }).where(eq(account.id, id));
};

export const backupOf = async (db: Db, id: string): Promise<Buffer | undefined> => {
  const [row] = await db.select({ backup: account.backup }).from(account).where(eq(account.id, id));
  return row?.backup ?? undefined;
};
