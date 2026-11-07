import { existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { isoSeconds, replaceAtomically } from "../src/io.ts";

describe("replaceAtomically", () => {
  const dir = (): string => mkdtempSync(join(tmpdir(), "pindoro-io-"));

  it("replaces the file with what was written", () => {
    const d = dir();
    const dest = join(d, "identity.json");
    writeFileSync(dest, "old");
    replaceAtomically(dest, (tmp) => writeFileSync(tmp, "new"));
    expect(readFileSync(dest, "utf8")).toBe("new");
    expect(readdirSync(d)).toEqual(["identity.json"]);
  });

  it("a failed write leaves the old file and no temp file", () => {
    const d = dir();
    const dest = join(d, "georgia.pmtiles");
    writeFileSync(dest, "live");
    expect(() =>
      replaceAtomically(dest, (tmp) => {
        writeFileSync(tmp, "half");
        throw new Error("download died");
      }),
    ).toThrow("download died");
    expect(readFileSync(dest, "utf8")).toBe("live");
    expect(readdirSync(d)).toEqual(["georgia.pmtiles"]);
  });

  it("the temp name never ends like the destination", () => {
    const d = dir();
    const dest = join(d, "georgia.pmtiles");
    replaceAtomically(dest, (tmp) => {
      expect(tmp.endsWith(".pmtiles")).toBe(false);
      writeFileSync(tmp, "x");
    });
    expect(existsSync(dest)).toBe(true);
  });
});

it("isoSeconds drops the milliseconds", () => {
  expect(isoSeconds(new Date("2026-11-05T22:17:00.123Z"))).toBe("2026-11-05T22:17:00Z");
});
