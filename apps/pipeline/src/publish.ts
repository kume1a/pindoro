import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { OUT_DIR, packsDir } from "./config.ts";
import { identityFile, stagedIdentityFile } from "./identity.ts";
import { isoSeconds, replaceAtomically } from "./io.ts";
import type { Manifest } from "./pack.ts";

const readManifest = (file: string): Manifest => JSON.parse(readFileSync(file, "utf8")) as Manifest;

/**
 * Copies the last built pack of `city` into PACKS_DIR, commits its street ids to the live
 * identity file and rewrites catalog.json. The manifest goes last: until it is swapped in, the API
 * keeps serving the previous pack.
 */
export const publish = (city: string): void => {
  const root = packsDir();
  const manifest = readManifest(join(OUT_DIR, city, "manifest.json"));
  const staged = stagedIdentityFile(city);
  if (!existsSync(staged)) throw new Error(`missing ${staged}; rebuild: pipeline build ${city}`);
  const dest = join(root, city);
  mkdirSync(dest, { recursive: true });
  replaceAtomically(join(dest, manifest.file), (tmp) =>
    copyFileSync(join(OUT_DIR, city, manifest.file), tmp),
  );
  mkdirSync(dirname(identityFile(city)), { recursive: true });
  replaceAtomically(identityFile(city), (tmp) => copyFileSync(staged, tmp));
  replaceAtomically(join(dest, "manifest.json"), (tmp) =>
    writeFileSync(tmp, `${JSON.stringify(manifest, null, 2)}\n`),
  );

  const cities = readdirSync(root, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(root, d.name, "manifest.json")))
    .map((d) => readManifest(join(root, d.name, "manifest.json")))
    .sort((a, b) => a.city.localeCompare(b.city))
    .map((m) => ({ ...m, url: `${m.city}/${m.file}` }));
  const catalog = { format_version: 1, generated_at: isoSeconds(new Date()), cities };
  replaceAtomically(join(root, "catalog.json"), (tmp) =>
    writeFileSync(tmp, `${JSON.stringify(catalog, null, 2)}\n`),
  );
  console.log(`published ${city} ${manifest.version} -> ${dest}; ids -> ${identityFile(city)}`);
};
