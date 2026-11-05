import { buildApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { runMigrations } from "./db/migrate.ts";

const config = loadConfig();
await runMigrations(config.DATABASE_URL);
const app = await buildApp(config);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, (): void => void app.close());
}

await app.listen({ host: config.HOST, port: config.PORT });
