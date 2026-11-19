import { describe, expect, it } from "vitest";
import { mapStyle, NAME_LAYERS, resolveToken, type TokenValue } from "../src/tiles.ts";

describe("resolveToken", () => {
  const tokens = new Map<string, TokenValue>([
    ["color.a", "#111111"],
    ["color.b", { light: "{color.a}", dark: "#222222" }],
    ["color.c", { light: "{color.b}", dark: "{color.b}" }],
  ]);

  it("follows aliases per theme", () => {
    expect(resolveToken(tokens, "color.c", "light")).toBe("#111111");
    expect(resolveToken(tokens, "color.c", "dark")).toBe("#222222");
  });

  it("fails on a missing token", () => {
    expect(() => resolveToken(tokens, "color.nope", "light")).toThrow("missing color.nope");
  });
});

it("map styles take only resolved hex colours from the tokens", () => {
  for (const mode of ["light", "dark"] as const) {
    expect(JSON.stringify(mapStyle(mode))).not.toMatch(/"\{color\./);
  }
});

it("map styles draw text only in the name layers, hidden, with glyphs from the tile server", () => {
  for (const mode of ["light", "dark"] as const) {
    const style = mapStyle(mode) as {
      glyphs?: string;
      layers: { id: string; layout?: { "text-field"?: unknown; visibility?: string } }[];
    };
    expect(style.glyphs).toMatch(/^\{TILES_BASE_URL\}\/font\//);
    const text = style.layers.filter((l) => l.layout?.["text-field"]);
    expect(text.map((l) => l.id)).toEqual(Object.values(NAME_LAYERS));
    expect(text.every((l) => l.layout?.visibility === "none")).toBe(true);
  }
});
