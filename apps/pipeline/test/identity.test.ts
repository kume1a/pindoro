import { describe, expect, it } from "vitest";
import { type Identity, jaccard, matchIdentities } from "../src/identity.ts";

const sequentialIds = (): (() => string) => {
  let n = 0;
  return () => `new-${++n}`;
};

const identity = (id: string, norm_name: string, way_ids: number[]): Identity => ({
  id,
  norm_name,
  name: norm_name,
  way_ids,
});

describe("jaccard", () => {
  it("is |A ∩ B| / |A ∪ B|", () => {
    expect(jaccard([1, 2, 3], [2, 3, 4])).toBe(0.5);
    expect(jaccard([1], [2])).toBe(0);
    expect(jaccard([], [])).toBe(0);
  });
});

describe("matchIdentities", () => {
  const existing = [identity("a", "rustaveli", [1, 2, 3, 4]), identity("b", "vazha", [10, 11])];

  it("keeps the id when the name matches and way overlap is >= 0.3", () => {
    const { ids, diff } = matchIdentities(
      existing,
      [
        { key: 1, norm_name: "rustaveli", name: "Rustaveli", way_ids: [1, 2, 5] },
        { key: 2, norm_name: "vazha", name: "Vazha", way_ids: [10, 11, 12] },
      ],
      "2026-11-05",
      sequentialIds(),
    );
    expect(ids.get(1)).toBe("a");
    expect(ids.get(2)).toBe("b");
    expect(diff).toEqual({ matched: 2, added: [], retired: [] });
  });

  it("issues a new id below the Jaccard threshold and retires the old one", () => {
    const { ids, identities, diff } = matchIdentities(
      existing,
      [
        { key: 1, norm_name: "rustaveli", name: "Rustaveli", way_ids: [1, 9, 8, 7] }, // 1/7 < 0.3
        { key: 2, norm_name: "vazha", name: "Vazha", way_ids: [10, 11] },
      ],
      "2026-11-05",
      sequentialIds(),
    );
    expect(ids.get(1)).toBe("new-1");
    expect(diff.retired).toEqual([{ id: "a", name: "rustaveli" }]);
    expect(identities.find((i) => i.id === "a")?.retired_at).toBe("2026-11-05");
  });

  it("never matches across different names even with identical ways", () => {
    const { ids } = matchIdentities(
      existing,
      [{ key: 1, norm_name: "rustaveli ave", name: "x", way_ids: [1, 2, 3, 4] }],
      "2026-11-05",
      sequentialIds(),
    );
    expect(ids.get(1)).toBe("new-1");
  });

  it("assigns one-to-one, best overlap first, when a street splits in two", () => {
    const { ids } = matchIdentities(
      existing,
      [
        { key: 1, norm_name: "rustaveli", name: "R", way_ids: [1] }, // 0.25
        { key: 2, norm_name: "rustaveli", name: "R", way_ids: [2, 3, 4] }, // 0.75
      ],
      "2026-11-05",
      sequentialIds(),
    );
    expect(ids.get(2)).toBe("a");
    expect(ids.get(1)).toBe("new-1");
  });

  it("keeps already retired identities untouched and never reuses them", () => {
    const retired = { ...identity("old", "vazha", [10, 11]), retired_at: "2025-01-01" };
    const { ids, identities } = matchIdentities(
      [retired],
      [{ key: 1, norm_name: "vazha", name: "Vazha", way_ids: [10, 11] }],
      "2026-11-05",
      sequentialIds(),
    );
    expect(ids.get(1)).toBe("new-1");
    expect(identities).toContainEqual(retired);
  });
});
