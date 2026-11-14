import type { FastifyInstance } from "fastify";
import postgres from "postgres";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { createDb, type Db } from "../src/db/client.ts";
import { runMigrations } from "../src/db/migrate.ts";
import { hashToken, newToken } from "../src/http.ts";
import { type Me, syncXp } from "../src/modules/leagues/leagues.service.ts";

const DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro_test";

// Wednesday of the week keyed 2026-11-09, and of the next one.
const WEEK = "2026-11-09";
const NEXT_WEEK = "2026-11-16";
const midweek = new Date("2026-11-11T12:00:00Z");
const nextMidweek = new Date("2026-11-18T12:00:00Z");

type Member = { rank: number; name: string; xp: number; zone: string; you: boolean };
type Standing = {
  league: { tier: number; week: string; ends_at: string; members: Member[] };
};

describe("leagues", () => {
  let clock = midweek;
  let app: FastifyInstance;
  const sql = postgres(DATABASE_URL, { max: 1, onnotice: () => {} });

  beforeAll(async () => {
    await runMigrations(DATABASE_URL);
    app = await buildApp(loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", DATABASE_URL }), {
      now: () => clock,
    });
  });

  beforeEach(async () => {
    clock = midweek;
    await sql`truncate account, league, league_member`;
  });

  afterAll(async () => {
    await app?.close();
    await sql.end();
  });

  // Straight into the table: the accounts tests cover signing up, and scrypt is slow.
  const signUp = async (username: string): Promise<{ me: Me; token: string }> => {
    const token = newToken();
    const [row] = await sql`
      insert into account (username, password_hash, token_hash)
      values (${username}, 'x', ${hashToken(token)}) returning id`;
    return { me: { id: row?.id, name: username }, token };
  };

  const join = async (username: string): Promise<string> => (await signUp(username)).token;

  const deleteAccount = (token: string): Promise<number> =>
    app
      .inject({
        method: "DELETE",
        url: "/v1/accounts/me",
        headers: { authorization: `Bearer ${token}` },
      })
      .then((r) => r.statusCode);

  const members = async (): Promise<unknown> =>
    (await sql`select count(*)::int as n from league_member`)[0]?.n;

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

  /** `count` accounts named p1…pn, each with `xp(i)` this week (i from 1); their tokens. */
  const crowd = async (count: number, xp: (i: number) => number): Promise<string[]> => {
    const tokens: string[] = [];
    for (let i = 1; i <= count; i++) {
      const token = await join(`p${i}`);
      await sync(token, xp(i));
      tokens.push(token);
    }
    return tokens;
  };

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
    const standing = await sync(await join("nino"), 0);
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
    expect(standing.league.members).toEqual([
      { rank: 1, name: "p1", xp: 500, zone: "up", you: false },
      { rank: 2, name: "p3", xp: 300, zone: "up", you: false },
      { rank: 3, name: "p2", xp: 200, zone: "up", you: true },
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
    const token = await join("nino");
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

  it("limits syncs per account", async () => {
    const token = await join("nino");
    const put = (): Promise<number> =>
      app
        .inject({
          method: "PUT",
          url: "/v1/league/me",
          headers: { authorization: `Bearer ${token}` },
          payload: { week: WEEK, xp: 10 },
        })
        .then((r) => r.statusCode);
    const codes = [];
    for (let i = 0; i < 31; i++) codes.push(await put());
    expect(codes.at(29)).toBe(200);
    expect(codes.at(30)).toBe(429);
  });

  it("drops a deleted account's places and turns its token away", async () => {
    const [stays, deleted] = await crowd(2, () => 10);
    expect(await deleteAccount(deleted as string)).toBe(204);
    const after = await app.inject({
      method: "PUT",
      url: "/v1/league/me",
      headers: { authorization: `Bearer ${deleted}` },
      payload: { week: WEEK, xp: 20 },
    });
    expect(after.statusCode).toBe(401);
    expect((await sync(stays as string, 10)).league.members).toEqual([
      { rank: 1, name: "p1", xp: 10, zone: "up", you: true },
    ]);
  });

  describe("a sync authenticated just before its account was deleted", () => {
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

    it("brings nothing back", async () => {
      const { me, token } = await signUp("nino");
      await sync(token, 10);
      expect(await deleteAccount(token)).toBe(204);
      expect(await syncXp(db, me, WEEK, 20, midweek)).toBe(false);
      expect(await members()).toBe(0);
    });

    it("waits for a delete in progress, then writes nothing", async () => {
      const { me } = await signUp("nino");
      let synced: Promise<boolean> | undefined;
      await sql.begin(async (tx) => {
        await tx`delete from account where id = ${me.id}`;
        synced = syncXp(db, me, WEEK, 20, midweek);
        await someoneWaitsOnALock();
      });
      expect(await synced).toBe(false);
      expect(await members()).toBe(0);
    });
  });
});
