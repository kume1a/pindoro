import type { FastifyInstance } from "fastify";
import postgres from "postgres";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { runMigrations } from "../src/db/migrate.ts";

const DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro_test";

// Wednesday of the week keyed 2026-11-09, and of the next one.
const WEEK = "2026-11-09";
const NEXT_WEEK = "2026-11-16";
const midweek = new Date("2026-11-11T12:00:00Z");
const nextMidweek = new Date("2026-11-18T12:00:00Z");

type Member = { rank: number; name: string; xp: number; zone: string; you: boolean };
type Standing = {
  player: { id: string; name: string };
  league: { tier: number; week: string; ends_at: string; members: Member[] };
};

describe("leagues", () => {
  let clock = midweek;
  let app: FastifyInstance;
  const sql = postgres(DATABASE_URL, { max: 1, onnotice: () => {} });

  beforeAll(async () => {
    await runMigrations(DATABASE_URL);
    app = await buildApp(
      loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", DATABASE_URL, SIGNUP_LIMIT: "1000" }),
      { now: () => clock },
    );
  });

  beforeEach(async () => {
    clock = midweek;
    await sql`truncate player, league, league_member`;
  });

  afterAll(async () => {
    await app?.close();
    await sql.end();
  });

  const join = async (name: string): Promise<string> => {
    const res = await app.inject({ method: "POST", url: "/v1/players", payload: { name } });
    expect(res.statusCode).toBe(201);
    return res.json().token;
  };

  const sync = async (token: string, xp: number, week = WEEK): Promise<Standing> => {
    const res = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers: { authorization: `Bearer ${token}` },
      payload: { week, xp },
    });
    expect(res.statusCode).toBe(200);
    return res.json();
  };

  /** `count` players named P1…Pn, each with `xp(i)` this week (i from 1); their tokens. */
  const crowd = async (count: number, xp: (i: number) => number): Promise<string[]> => {
    const tokens: string[] = [];
    for (let i = 1; i <= count; i++) {
      const token = await join(`P${"abcdefghijklmnopqrstuvwxyzabcdefghij"[i - 1]}`);
      await sync(token, xp(i));
      tokens.push(token);
    }
    return tokens;
  };

  it("creates a player with a tidied name and a token", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/players",
      payload: { name: "  Nino   K. " },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.player).toEqual({ id: expect.any(String), name: "Nino K." });
    expect(body.token).toMatch(/^[\w-]{40,}$/);
    const [row] = await sql`select token_hash from player`;
    expect(row?.token_hash).not.toBe(body.token);
  });

  it("rejects names that break the rule", async () => {
    for (const name of ["A", "Player 42", "Nino 🚗"]) {
      const res = await app.inject({ method: "POST", url: "/v1/players", payload: { name } });
      expect(res.statusCode).toBe(400);
    }
  });

  it("needs a known token", async () => {
    const missing = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      payload: { week: WEEK, xp: 10 },
    });
    const wrong = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers: { authorization: "Bearer nope" },
      payload: { week: WEEK, xp: 10 },
    });
    expect([missing.statusCode, wrong.statusCode]).toEqual([401, 401]);
  });

  it("has no league until the player earns XP this week", async () => {
    const standing = await sync(await join("Nino"), 0);
    expect(standing.league).toEqual({
      tier: 0,
      week: WEEK,
      ends_at: "2026-11-15T20:00:00.000Z",
      members: [],
    });
  });

  it("ranks members by XP and never lowers it", async () => {
    const [nino, giorgi, ana] = await crowd(3, (i) => i * 100);
    await sync(nino as string, 500);
    const standing = await sync(giorgi as string, 50);
    expect(standing.player.name).toBe("Pb");
    expect(standing.league.members).toEqual([
      { rank: 1, name: "Pa", xp: 500, zone: "up", you: false },
      { rank: 2, name: "Pc", xp: 300, zone: "up", you: false },
      { rank: 3, name: "Pb", xp: 200, zone: "up", you: true },
    ]);
    expect((await sync(ana as string, 300)).league.members[1]?.you).toBe(true);
  });

  it("puts the earlier of two equal players first", async () => {
    const [, second] = await crowd(2, () => 100);
    const standing = await sync(second as string, 100);
    expect(standing.league.members.map((m) => m.you)).toEqual([false, true]);
  });

  it("opens a second league for the 31st player", async () => {
    const tokens = await crowd(31, (i) => i);
    const last = await sync(tokens[30] as string, 31);
    expect(last.league.members).toHaveLength(1);
    const first = await sync(tokens[0] as string, 1);
    expect(first.league.members).toHaveLength(30);
    expect(first.league.members.at(-1)).toMatchObject({ rank: 30, you: true, zone: "stay" });
  });

  it("ignores XP sent for another week", async () => {
    const token = await join("Nino");
    const standing = await sync(token, 400, "2026-11-02");
    expect(standing.league.members).toEqual([]);
  });

  it("moves the top 5 up a league the next week", async () => {
    const tokens = await crowd(7, (i) => 100 - i);
    clock = nextMidweek;
    const [top, , , , fifth, sixth] = await Promise.all(tokens.map((t) => sync(t, 0, NEXT_WEEK)));
    expect([top, fifth, sixth].map((s) => s?.league.tier)).toEqual([1, 1, 0]);
    const promoted = await sync(tokens[0] as string, 10, NEXT_WEEK);
    expect(promoted.league).toMatchObject({ tier: 1, week: NEXT_WEEK });
    expect(promoted.league.members).toHaveLength(1);
  });

  it("renames a player and deletes one", async () => {
    const token = await join("Nino");
    const auth = { authorization: `Bearer ${token}` };
    const renamed = await app.inject({
      method: "PATCH",
      url: "/v1/players/me",
      headers: auth,
      payload: { name: "Nino Kapanadze" },
    });
    expect(renamed.json()).toMatchObject({ name: "Nino Kapanadze" });
    await sync(token, 10);
    const gone = await app.inject({ method: "DELETE", url: "/v1/players/me", headers: auth });
    expect(gone.statusCode).toBe(204);
    const after = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers: auth,
      payload: { week: WEEK, xp: 10 },
    });
    expect(after.statusCode).toBe(401);
    const [left] = await sql`select count(*)::int as n from league_member`;
    expect(left?.n).toBe(0);
  });
});

describe("signup limit", () => {
  it("allows SIGNUP_LIMIT new players per address per hour", async () => {
    await runMigrations(DATABASE_URL);
    const app = await buildApp(
      loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", DATABASE_URL, SIGNUP_LIMIT: "2" }),
    );
    const post = (ip: string): Promise<number> =>
      app
        .inject({
          method: "POST",
          url: "/v1/players",
          headers: { "cf-connecting-ip": ip },
          payload: { name: "Nino" },
        })
        .then((r) => r.statusCode);
    expect([await post("1.1.1.1"), await post("1.1.1.1"), await post("1.1.1.1")]).toEqual([
      201, 201, 429,
    ]);
    expect(await post("2.2.2.2")).toBe(201);
    await app.close();
  });
});
