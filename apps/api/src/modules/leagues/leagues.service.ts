import { and, asc, count, desc, eq, lt, type SQL, sql } from "drizzle-orm";
import type { Static } from "typebox";
import type { Db } from "../../db/client.ts";
import { account, league, leagueMember } from "../../db/schema.ts";
import { hashToken } from "../../http.ts";
import { LEAGUE, leagueWeek, nextTier, zone } from "./leagues.rules.ts";
import type { Standing } from "./leagues.schemas.ts";

type Tx = Db | Parameters<Parameters<Db["transaction"]>[0]>[0];
/** A signed-in account: its id and its username, the name the league shows. */
export type Me = { id: string; name: string };
type Place = { leagueId: string; tier: number };

const memberIn = (accountId: string, week: string): SQL | undefined =>
  and(eq(leagueMember.accountId, accountId), eq(leagueMember.week, week));

const keepHigherXp = (xp: number): SQL => sql`greatest(${leagueMember.xp}, ${xp})`;

/** The league `accountId` plays in `week`, if any. */
const placeIn = async (db: Tx, accountId: string, week: string): Promise<Place | undefined> => {
  const [place] = await db
    .select({ leagueId: leagueMember.leagueId, tier: league.tier })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(memberIn(accountId, week));
  return place;
};

/** Holds the account until the transaction ends, so a delete waits; false once it's gone. */
const lockAccount = async (tx: Tx, id: string): Promise<boolean> => {
  const [row] = await tx
    .select({ id: account.id })
    .from(account)
    .where(eq(account.id, id))
    .for("key share");
  return row !== undefined;
};

export const accountByToken = async (db: Db, token: string): Promise<Me | undefined> => {
  const [row] = await db
    .select({ id: account.id, name: account.username })
    .from(account)
    .where(eq(account.tokenHash, hashToken(token)));
  return row;
};

/** Serialises joins per week and tier, so two players never both take a league's last place. */
const lockJoins = async (tx: Tx, week: string, tier: number): Promise<void> => {
  await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${`league:${week}:${tier}`}))`);
};

/** A league's members, best first: most XP, then the earliest to join. */
const ranked = (
  db: Tx,
  leagueId: string,
): Promise<{ accountId: string; name: string; xp: number }[]> =>
  db
    .select({ accountId: leagueMember.accountId, name: account.username, xp: leagueMember.xp })
    .from(leagueMember)
    .innerJoin(account, eq(account.id, leagueMember.accountId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(desc(leagueMember.xp), asc(leagueMember.joinedAt), asc(leagueMember.accountId));

/** The tier `accountId` plays in `week`: from their last league's result, Alley at first. */
const tierFor = async (db: Tx, accountId: string, week: string): Promise<number> => {
  const [last] = await db
    .select({ leagueId: leagueMember.leagueId, tier: league.tier })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(and(eq(leagueMember.accountId, accountId), lt(leagueMember.week, week)))
    .orderBy(desc(leagueMember.week))
    .limit(1);
  if (!last) return 0;
  const rank = (await ranked(db, last.leagueId)).findIndex((m) => m.accountId === accountId) + 1;
  return nextTier(rank, last.tier);
};

/** The newest league of `week` and `tier` with room, or a new one. Call under the join lock. */
const openLeague = async (tx: Tx, week: string, tier: number): Promise<string> => {
  const [open] = await tx
    .select({ id: league.id })
    .from(league)
    .leftJoin(leagueMember, eq(leagueMember.leagueId, league.id))
    .where(and(eq(league.week, week), eq(league.tier, tier)))
    .groupBy(league.id)
    .having(sql`${count(leagueMember.accountId)} < ${LEAGUE.size}`)
    .orderBy(desc(league.createdAt))
    .limit(1);
  if (open) return open.id;
  const [created] = await tx.insert(league).values({ week, tier }).returning({ id: league.id });
  if (!created) throw new Error("league insert returned nothing");
  return created.id;
};

/** The account's league this week, as the app shows it. */
export const standing = async (db: Db, me: Me, now: Date): Promise<Static<typeof Standing>> => {
  const week = leagueWeek(now);
  const place = await placeIn(db, me.id, week.key);
  const tier = place?.tier ?? (await tierFor(db, me.id, week.key));
  const members = place ? await ranked(db, place.leagueId) : [];
  return {
    league: {
      tier,
      week: week.key,
      ends_at: week.end.toISOString(),
      members: members.map((m, i) => ({
        rank: i + 1,
        name: m.name,
        xp: m.xp,
        zone: zone(i + 1, tier),
        you: m.accountId === me.id,
      })),
    },
  };
};

/**
 * Records `xp` as the player's XP for `week` when it is the current week (it never goes down),
 * joining a league on the first XP; XP for an earlier week is ignored. False, with nothing
 * written, when the account was deleted since it was authenticated.
 */
export const syncXp = async (
  db: Db,
  me: Me,
  week: string,
  xp: number,
  now: Date,
): Promise<boolean> => {
  const current = leagueWeek(now).key;
  if (week !== current || xp === 0) return true;
  return db.transaction(async (tx) => {
    // Before any league row or lock: a delete takes the account first, then cascades to them.
    if (!(await lockAccount(tx, me.id))) return false;
    const [kept] = await tx
      .update(leagueMember)
      .set({ xp: keepHigherXp(xp) })
      .where(memberIn(me.id, week))
      .returning({ week: leagueMember.week });
    if (kept) return true;
    const tier = await tierFor(tx, me.id, week);
    await lockJoins(tx, week, tier);
    const leagueId = await openLeague(tx, week, tier);
    await tx
      .insert(leagueMember)
      .values({ accountId: me.id, week, leagueId, xp })
      .onConflictDoUpdate({
        target: [leagueMember.accountId, leagueMember.week],
        set: { xp: keepHigherXp(xp) },
      });
    return true;
  });
};
