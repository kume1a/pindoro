import { createHash, randomBytes } from "node:crypto";
import { and, asc, count, desc, eq, lt, sql } from "drizzle-orm";
import type { Static } from "typebox";
import type { Db } from "../../db/client.ts";
import { league, leagueMember, player } from "../../db/schema.ts";
import { LEAGUE, leagueWeek, nextTier, zone } from "./leagues.rules.ts";
import type { Player, Standing } from "./leagues.schemas.ts";

type Tx = Db | Parameters<Parameters<Db["transaction"]>[0]>[0];
type PlayerNode = Static<typeof Player>;

const hashToken = (token: string): string => createHash("sha256").update(token).digest("hex");

export const createPlayer = async (
  db: Db,
  name: string,
): Promise<{ player: PlayerNode; token: string }> => {
  const token = randomBytes(32).toString("base64url");
  const [row] = await db
    .insert(player)
    .values({ name, tokenHash: hashToken(token) })
    .returning({ id: player.id, name: player.name });
  if (!row) throw new Error("player insert returned nothing");
  return { player: row, token };
};

export const playerByToken = async (db: Db, token: string): Promise<PlayerNode | undefined> => {
  const [row] = await db
    .select({ id: player.id, name: player.name })
    .from(player)
    .where(eq(player.tokenHash, hashToken(token)));
  return row;
};

export const renamePlayer = async (db: Db, id: string, name: string): Promise<PlayerNode> => {
  await db.update(player).set({ name }).where(eq(player.id, id));
  return { id, name };
};

export const deletePlayer = async (db: Db, id: string): Promise<void> => {
  await db.delete(player).where(eq(player.id, id));
};

/** A league's members, best first: most XP, then the earliest to join. */
const ranked = (
  db: Tx,
  leagueId: string,
): Promise<{ playerId: string; name: string; xp: number }[]> =>
  db
    .select({ playerId: leagueMember.playerId, name: player.name, xp: leagueMember.xp })
    .from(leagueMember)
    .innerJoin(player, eq(player.id, leagueMember.playerId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(desc(leagueMember.xp), asc(leagueMember.joinedAt), asc(leagueMember.playerId));

/** The tier `playerId` plays in `week`: from their last league's result, Alley at first. */
const tierFor = async (db: Tx, playerId: string, week: string): Promise<number> => {
  const [last] = await db
    .select({ leagueId: leagueMember.leagueId, tier: league.tier })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(and(eq(leagueMember.playerId, playerId), lt(leagueMember.week, week)))
    .orderBy(desc(leagueMember.week))
    .limit(1);
  if (!last) return 0;
  const rank = (await ranked(db, last.leagueId)).findIndex((m) => m.playerId === playerId) + 1;
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
    .having(sql`${count(leagueMember.playerId)} < ${LEAGUE.size}`)
    .orderBy(desc(league.createdAt))
    .limit(1);
  if (open) return open.id;
  const [created] = await tx.insert(league).values({ week, tier }).returning({ id: league.id });
  if (!created) throw new Error("league insert returned nothing");
  return created.id;
};

/** The player and their league this week, as the app shows it. */
export const standing = async (
  db: Db,
  me: PlayerNode,
  now: Date,
): Promise<Static<typeof Standing>> => {
  const week = leagueWeek(now);
  const [place] = await db
    .select({ leagueId: leagueMember.leagueId, tier: league.tier })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(and(eq(leagueMember.playerId, me.id), eq(leagueMember.week, week.key)));
  const tier = place?.tier ?? (await tierFor(db, me.id, week.key));
  const members = place ? await ranked(db, place.leagueId) : [];
  return {
    player: me,
    league: {
      tier,
      week: week.key,
      ends_at: week.end.toISOString(),
      members: members.map((m, i) => ({
        rank: i + 1,
        name: m.name,
        xp: m.xp,
        zone: zone(i + 1, tier),
        you: m.playerId === me.id,
      })),
    },
  };
};

/**
 * Records `xp` as the player's XP for `week` when it is the current week (it never goes down),
 * joining a league on the first XP; XP for an earlier week is ignored.
 */
export const syncXp = async (
  db: Db,
  me: PlayerNode,
  week: string,
  xp: number,
  now: Date,
): Promise<void> => {
  const current = leagueWeek(now).key;
  if (week !== current || xp === 0) return;
  await db.transaction(async (tx) => {
    const [kept] = await tx
      .update(leagueMember)
      .set({ xp: sql`greatest(${leagueMember.xp}, ${xp})` })
      .where(and(eq(leagueMember.playerId, me.id), eq(leagueMember.week, week)))
      .returning({ week: leagueMember.week });
    if (kept) return;
    const tier = await tierFor(tx, me.id, week);
    // Serialises joins per week and tier, so two players never both take a league's last place.
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${`league:${week}:${tier}`}))`);
    const leagueId = await openLeague(tx, week, tier);
    await tx
      .insert(leagueMember)
      .values({ playerId: me.id, week, leagueId, xp })
      .onConflictDoUpdate({
        target: [leagueMember.playerId, leagueMember.week],
        set: { xp: sql`greatest(${leagueMember.xp}, ${xp})` },
      });
  });
};
