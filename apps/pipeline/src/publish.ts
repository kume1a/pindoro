import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { OUT_DIR, packsDir } from "./config.ts";
import type { Manifest } from "./pack.ts";

/** Readers never see a half-written file: write a sibling temp file, then rename over. */
const replaceAtomically = (dest: string, write: (tmp: string) => void): void => {
  const tmp = `${dest}.${process.pid}.tmp`;
  write(tmp);
  renameSync(tmp, dest);
};

const readManifest = (file: string): Manifest => JSON.parse(readFileSync(file, "utf8")) as Manifest;

/** Copies the last built pack of `city` into PACKS_DIR and rewrites catalog.json. */
export const publish = (city: string): void => {
  const root = packsDir();
  const manifest = readManifest(join(OUT_DIR, city, "manifest.json"));
  const dest = join(root, city);
  mkdirSync(dest, { recursive: true });
  replaceAtomically(join(dest, manifest.file), (tmp) =>
    copyFileSync(join(OUT_DIR, city, manifest.file), tmp),
  );
  replaceAtomically(join(dest, "manifest.json"), (tmp) =>
    writeFileSync(tmp, `${JSON.stringify(manifest, null, 2)}\n`),
  );

  const cities = readdirSync(root, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(root, d.name, "manifest.json")))
    .map((d) => readManifest(join(root, d.name, "manifest.json")))
    .sort((a, b) => a.city.localeCompare(b.city))
    .map((m) => ({ ...m, url: `${m.city}/${m.file}` }));
  const catalog = { format_version: 1, generated_at: new Date().toISOString(), cities };
  replaceAtomically(join(root, "catalog.json"), (tmp) =>
    writeFileSync(tmp, `${JSON.stringify(catalog, null, 2)}\n`),
  );
  console.log(`published ${city} ${manifest.version} -> ${dest}`);
};
