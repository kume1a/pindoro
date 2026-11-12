import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { readNeighbourhoods } from "../src/load.ts";

const point = { type: "Point", coordinates: [44.75, 41.72] };

/** A curated neighbourhoods file with one feature per properties object. */
const curated = (...properties: Record<string, string>[]): string => {
  const file = join(mkdtempSync(join(tmpdir(), "pindoro-curation-")), "neighbourhoods.geojson");
  const features = properties.map((p) => ({ type: "Feature", properties: p, geometry: point }));
  writeFileSync(file, JSON.stringify({ type: "FeatureCollection", features }));
  return file;
};

describe("readNeighbourhoods", () => {
  it("trims the names and leaves out a blank English name", () => {
    const file = curated(
      { slug: "padded", name_ka: "  ვაკე ", name_en: " Vake  " },
      { slug: "empty", name_ka: "საბურთალო", name_en: "" },
      { slug: "blank", name_ka: "ნაძალადევი", name_en: "   " },
      { slug: "missing", name_ka: "დიდუბე" },
    );
    expect(
      readNeighbourhoods(file).map(({ slug, name_ka, name_en }) => [slug, name_ka, name_en]),
    ).toEqual([
      ["padded", "ვაკე", "Vake"],
      ["empty", "საბურთალო", undefined],
      ["blank", "ნაძალადევი", undefined],
      ["missing", "დიდუბე", undefined],
    ]);
  });

  it("rejects a feature whose name_ka is blank", () => {
    const file = curated({ slug: "ok", name_ka: "ვაკე" }, { slug: "blank", name_ka: "  " });
    expect(() => readNeighbourhoods(file)).toThrow(/feature 1 needs properties slug and name_ka/);
  });
});
