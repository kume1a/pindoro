import type { FastifyInstance } from "fastify";
import postgres from "postgres";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { createDb, type Db } from "../src/db/client.ts";
import { runMigrations } from "../src/db/migrate.ts";
import { renamePlayer, syncXp } from "../src/modules/leagues/leagues.service.ts";

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

  const signUp = async (
    name: string,
  ): Promise<{ player: { id: string; name: string }; token: string }> => {
    const res = await app.inject({ method: "POST", url: "/v1/players", payload: { name } });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const join = async (name: string): Promise<string> => (await signUp(name)).token;

  const leave = (token: string): Promise<number> =>
    app
      .inject({
        method: "DELETE",
        url: "/v1/players/me",
        headers: { authorization: `Bearer ${token}` },
      })
      .then((r) => r.statusCode);

  const members = async (): Promise<unknown> =>
    (await sql`select count(*)::int as n from league_member`)[0]?.n;

  const leagues = async (): Promise<unknown> =>
    (await sql`select count(*)::int as n from league`)[0]?.n;

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

  it("keeps a finished week's ranks when a player leaves after it", async () => {
    const tokens = await crowd(7, (i) => 100 - i);
    clock = nextMidweek;
    expect(await leave(tokens[4] as string)).toBe(204);
    const sixth = await sync(tokens[5] as string, 0, NEXT_WEEK);
    expect(sixth.league.tier).toBe(0);
  });

  it("limits renames and syncs per player", async () => {
    const token = await join("Nino");
    const rename = (): Promise<number> =>
      app
        .inject({
          method: "PATCH",
          url: "/v1/players/me",
          headers: { authorization: `Bearer ${token}` },
          payload: { name: "Nino" },
        })
        .then((r) => r.statusCode);
    const codes = [];
    for (let i = 0; i < 31; i++) codes.push(await rename());
    expect(codes.at(29)).toBe(200);
    expect(codes.at(30)).toBe(429);
  });

  it("renames a player and forgets one", async () => {
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
    expect(await leave(token)).toBe(204);
    const after = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers: auth,
      payload: { week: WEEK, xp: 10 },
    });
    expect(after.statusCode).toBe(401);
    expect(await members()).toBe(0);
    expect(await sql`select name from player`).toEqual([{ name: "" }]);
  });

  it("turns away a sync and a rename with a left player's token", async () => {
    const token = await join("Nino");
    await sync(token, 10);
    expect(await leave(token)).toBe(204);
    const headers = { authorization: `Bearer ${token}` };
    const synced = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers,
      payload: { week: WEEK, xp: 20 },
    });
    const renamed = await app.inject({
      method: "PATCH",
      url: "/v1/players/me",
      headers,
      payload: { name: "Nino" },
    });
    expect([synced.statusCode, renamed.statusCode]).toEqual([401, 401]);
    expect(await members()).toBe(0);
    expect(await sql`select name from player`).toEqual([{ name: "" }]);
  });

  it("drops this week's league when its last player leaves", async () => {
    const [stays, leaves] = await crowd(2, () => 10);
    await leave(leaves as string);
    expect(await leagues()).toBe(1);
    await leave(stays as string);
    expect(await leagues()).toBe(0);
  });

  describe("a request authenticated just before its player left", () => {
    let db: Db;

    beforeAll(() => {
      db = createDb(DATABASE_URL);
    });

    afterAll(async () => {
      await db.$client.end();
    });

    /** Resolves once a backend of this database waits on a row lock. */
    const someoneWaitsOnALock = async (): Promise<void> => {
      for (let attempt = 0; attempt < 100; attempt++) {
        const [row] = await db.$client`
          select count(*)::int as n from pg_locks l join pg_stat_activity a using (pid)
          where not l.granted and a.datname = current_database()`;
        if (row?.n > 0) return;
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
      throw new Error("nobody waited on a lock");
    };

    it("brings nothing back: no league place, no name", async () => {
      const { player: me, token } = await signUp("Nino");
      await sync(token, 10);
      expect(await leave(token)).toBe(204);
      expect(await syncXp(db, me, WEEK, 20, midweek)).toBe(false);
      expect(await renamePlayer(db, me.id, "Nino")).toBeUndefined();
      expect(await members()).toBe(0);
      expect(await leagues()).toBe(0);
      expect(await sql`select name from player`).toEqual([{ name: "" }]);
    });

    it("a sync waits for a leave in progress, then writes nothing", async () => {
      const { player: me, token } = await signUp("Nino");
      await sync(token, 10);
      let synced: Promise<boolean> | undefined;
      // What forgetPlayer does, held open until the sync is waiting on it.
      await sql.begin(async (tx) => {
        await tx`update player set name = '', token_hash = ${`left:${me.id}`} where id = ${me.id}`;
        await tx`delete from league_member where player_id = ${me.id}`;
        synced = syncXp(db, me, WEEK, 20, midweek);
        await someoneWaitsOnALock();
      });
      expect(await synced).toBe(false);
      expect(await members()).toBe(0);
    });
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
