import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { loadConfig } from "../config.ts";

const migrationsFolder = fileURLToPath(new URL("../../drizzle", import.meta.url));

export const runMigrations = async (url: string): Promise<void> => {
  const sql = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await migrate(drizzle(sql), { migrationsFolder });
  } finally {
    await sql.end();
  }
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await runMigrations(loadConfig().DATABASE_URL);
}
