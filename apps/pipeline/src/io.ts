import { execFileSync } from "node:child_process";
import { renameSync, rmSync, writeFileSync } from "node:fs";

/** Runs a tool, returns its stdout; `env` is added to this process's environment. */
export const run = (cmd: string, args: string[], env?: Record<string, string>): string =>
  execFileSync(cmd, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
    env: env && { ...process.env, ...env },
  });

/**
 * Readers never see a half-written file: write a sibling temp file, then rename over. The temp
 * name never ends like `dest`, so directory scanners (martin's *.pmtiles) skip it.
 */
export const replaceAtomically = (dest: string, write: (tmp: string) => void): void => {
  const tmp = `${dest}.${process.pid}.tmp`;
  try {
    write(tmp);
    renameSync(tmp, dest);
  } catch (e) {
    rmSync(tmp, { force: true });
    throw e;
  }
};

/** Pretty-printed with a trailing newline, as every JSON file the pipeline writes. */
export const writeJson = (file: string, value: unknown): void =>
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);

/** An ISO timestamp without milliseconds, e.g. 2026-11-05T22:17:00Z. */
export const isoSeconds = (at: Date): string => at.toISOString().replace(/\.\d+Z$/, "Z");
