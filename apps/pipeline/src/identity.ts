import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { cityDir, OUT_DIR } from "./config.ts";
import { replaceAtomically } from "./io.ts";

export interface Identity {
  id: string;
  norm_name: string;
  name: string;
  way_ids: number[];
  retired_at?: string;
}

export interface CurrentStreet {
  key: number;
  norm_name: string;
  name: string;
  way_ids: number[];
}

interface IdentityDiff {
  matched: number;
  added: { id: string; name: string }[];
  retired: { id: string; name: string }[];
}

interface IdentityResult {
  ids: Map<number, string>;
  identities: Identity[];
  diff: IdentityDiff;
}

const JACCARD_MIN = 0.3;

export const jaccard = (a: number[], b: number[]): number => {
  const sa = new Set(a);
  const sb = new Set(b);
  let shared = 0;
  for (const x of sb) if (sa.has(x)) shared++;
  const union = sa.size + sb.size - shared;
  return union === 0 ? 0 : shared / union;
};

/**
 * Keeps street ids stable across rebuilds: a street inherits the id of an active identity with the same
 * normalised name and way-id Jaccard >= 0.3 (best pairs first, one-to-one). Others get new ids;
 * active identities left unmatched are retired.
 */
export const matchIdentities = (
  existing: Identity[],
  current: CurrentStreet[],
  today: string,
  newId: () => string = randomUUID,
): IdentityResult => {
  const active = existing.filter((i) => !i.retired_at);
  const byName = Map.groupBy(active, (i) => i.norm_name);

  const pairs = current.flatMap((street) =>
    (byName.get(street.norm_name) ?? [])
      .map((identity) => ({ street, identity, score: jaccard(identity.way_ids, street.way_ids) }))
      .filter((p) => p.score >= JACCARD_MIN),
  );
  pairs.sort(
    (a, b) =>
      b.score - a.score ||
      a.identity.id.localeCompare(b.identity.id) ||
      a.street.key - b.street.key,
  );

  const ids = new Map<number, string>();
  const used = new Set<string>();
  for (const { street, identity } of pairs) {
    if (ids.has(street.key) || used.has(identity.id)) continue;
    ids.set(street.key, identity.id);
    used.add(identity.id);
  }

  const added: IdentityDiff["added"] = [];
  for (const street of current) {
    if (ids.has(street.key)) continue;
    const id = newId();
    ids.set(street.key, id);
    added.push({ id, name: street.name });
  }
  const retired = active.filter((i) => !used.has(i.id));

  const identities: Identity[] = [
    ...existing.filter((i) => i.retired_at),
    ...retired.map((i) => ({ ...i, retired_at: today })),
    ...current.map((s) => ({
      id: ids.get(s.key) as string,
      norm_name: s.norm_name,
      name: s.name,
      way_ids: s.way_ids,
    })),
  ].sort((a, b) => a.norm_name.localeCompare(b.norm_name) || a.id.localeCompare(b.id));

  return {
    ids,
    identities,
    diff: {
      matched: used.size,
      added,
      retired: retired.map((i) => ({ id: i.id, name: i.name })),
    },
  };
};

const committedIdentityFile = (city: string): string => join(cityDir(city), "identity.json");

/**
 * The city's live identities: the ones its published packs use. On the server they sit in
 * IDENTITY_DIR (next to the packs); elsewhere they are the committed data/cities file.
 */
export const identityFile = (city: string): string => {
  const dir = process.env.IDENTITY_DIR;
  return dir ? join(dir, city, "identity.json") : committedIdentityFile(city);
};

/** A full build's identities wait here until `publish` makes its pack live. */
export const stagedIdentityFile = (city: string): string => join(OUT_DIR, city, "identity.json");

/** The live identities, seeded from the committed file until the server has its own. */
export const readIdentities = (city: string): Identity[] => {
  const file = [identityFile(city), committedIdentityFile(city)].find((f) => existsSync(f));
  return file ? (JSON.parse(readFileSync(file, "utf8")) as { streets: Identity[] }).streets : [];
};

/** One street per line keeps the committed file reviewable in diffs. */
export const writeIdentities = (file: string, identities: Identity[]): void => {
  const lines = identities.map((i) => `\n    ${JSON.stringify(i)}`).join(",");
  replaceAtomically(file, (tmp) =>
    writeFileSync(tmp, `{\n  "streets": [${lines}${lines && "\n  "}]\n}\n`),
  );
};
