import { customType, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

const bytea = customType<{ data: Buffer }>({ dataType: () => "bytea" });

// A player's sign-in and progress backup (the app's SQLite file, gzipped). The password is a salted
// scrypt hash; the token and the recovery code (null on accounts made before codes) are sha256
// hashes.
export const account = pgTable("account", {
  id: uuid().primaryKey().defaultRandom(),
  username: text().notNull().unique(),
  passwordHash: text().notNull(),
  tokenHash: text().notNull().unique(),
  recoveryHash: text(),
  backup: bytea(),
  backupAt: timestamp({ withTimezone: true }),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});
