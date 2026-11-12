import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { build, fetchExtract } from "./build.ts";
import { buildDir, builtManifestFile } from "./config.ts";
import { readManifest } from "./pack.ts";
import { publish } from "./publish.ts";
import { tiles } from "./tiles.ts";
import { validatePack } from "./validate.ts";

const USAGE = `usage: pipeline <command>
  fetch <city>              download the OSM extract from city.yaml (skipped when fresh)
  build <city> [--fixture]  osmium + osm2pgsql + SQL steps + stable ids + pack export
  validate <pack|city>      check a .sqlite / .sqlite.gz pack (or a city's last build) and print a summary
  publish <city>            copy the last built pack into PACKS_DIR and commit its street ids
  tiles [--styles-only]     extract Georgia from the latest Protomaps build + write map styles`;

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    fixture: { type: "boolean", default: false },
    "styles-only": { type: "boolean", default: false },
  },
});
const [command, arg] = positionals;

const required = (): string => {
  if (!arg) throw new Error(USAGE);
  return arg;
};

// pnpm runs the script inside apps/pipeline/; resolve user paths against where it was invoked.
const userPath = (p: string): string => resolve(process.env.INIT_CWD ?? process.cwd(), p);

// A city id resolves to its last built pack in apps/pipeline/out/<city>.
const packPath = (arg: string): string => {
  const path = userPath(arg);
  if (existsSync(path)) return path;
  const manifest = builtManifestFile(arg);
  if (!existsSync(manifest)) throw new Error(`no pack file or built city named ${arg}`);
  return join(buildDir(arg), readManifest(manifest).file);
};

const commands: Record<string, () => Promise<void> | void> = {
  fetch: async () => {
    await fetchExtract(required());
  },
  build: () => build(required(), { fixture: values.fixture }),
  validate: () => {
    if (!validatePack(packPath(required()))) process.exitCode = 1;
  },
  publish: () => publish(required()),
  tiles: () => tiles({ stylesOnly: values["styles-only"] }),
};

const handler = command ? commands[command] : undefined;
if (!handler) {
  console.error(USAGE);
  process.exitCode = 2;
} else {
  try {
    await handler();
  } catch (e) {
    console.error(e instanceof Error ? e.message : e);
    process.exitCode = 1;
  }
}
