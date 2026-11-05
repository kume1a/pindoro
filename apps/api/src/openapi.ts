import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { buildApp } from "./app.ts";
import { loadConfig } from "./config.ts";

// Built from defaults only (never the caller's env) so the output is reproducible. No DB is touched.
const app = await buildApp(loadConfig({ NODE_ENV: "production", LOG_LEVEL: "silent" }));
await app.ready();
const out = fileURLToPath(new URL("../../../shared/openapi/openapi.json", import.meta.url));
await writeFile(out, `${JSON.stringify(app.swagger(), null, 2)}\n`);
await app.close();
console.log(`wrote ${out}`);
