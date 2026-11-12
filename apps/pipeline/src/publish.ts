import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { buildDir, builtManifestFile, packsDir, stagedIdentityFile } from "./config.ts";
import { identityFile } from "./identity.ts";
import { replaceAtomically, writeJson } from "./io.ts";
import { readManifest } from "./pack.ts";

/**
 * Copies the last built pack of `city` into PACKS_DIR and commits its street ids to the live
 * identity file. The manifest goes last: until it is swapped in, the API keeps serving the
 * previous pack.
 */
export const publish = (city: string): void => {
  const manifest = readManifest(builtManifestFile(city));
  const staged = stagedIdentityFile(city);
  if (!existsSync(staged)) throw new Error(`missing ${staged}; rebuild: pipeline build ${city}`);
  const dest = join(packsDir(), city);
  mkdirSync(dest, { recursive: true });
  replaceAtomically(join(dest, manifest.file), (tmp) =>
    copyFileSync(join(buildDir(city), manifest.file), tmp),
  );
  mkdirSync(dirname(identityFile(city)), { recursive: true });
  replaceAtomically(identityFile(city), (tmp) => copyFileSync(staged, tmp));
  replaceAtomically(join(dest, "manifest.json"), (tmp) => writeJson(tmp, manifest));
  console.log(`published ${city} ${manifest.version} -> ${dest}; ids -> ${identityFile(city)}`);
};
