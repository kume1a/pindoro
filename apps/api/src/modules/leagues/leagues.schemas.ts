import { Type } from "typebox";
import { LEAGUE } from "./leagues.rules.ts";

export const Player = Type.Object({
  id: Type.String({ format: "uuid" }),
  name: Type.String(),
});

// The name is checked with isLeagueName after trimming; this only bounds the input.
export const NameBody = Type.Object({ name: Type.String({ maxLength: 100 }) });

export const NewPlayer = Type.Object({ player: Player, token: Type.String() });

export const XpBody = Type.Object({
  week: Type.String({ format: "date" }),
  xp: Type.Integer({ minimum: 0, maximum: 1_000_000 }),
});

const Member = Type.Object({
  rank: Type.Integer({ minimum: 1 }),
  name: Type.String(),
  xp: Type.Integer(),
  zone: Type.Union([Type.Literal("up"), Type.Literal("stay"), Type.Literal("down")]),
  you: Type.Boolean(),
});

// The player and their league this week; `members` is empty until they earn XP this week.
export const Standing = Type.Object({
  player: Player,
  league: Type.Object({
    tier: Type.Integer({ minimum: 0, maximum: LEAGUE.tiers - 1 }),
    week: Type.String({ format: "date" }),
    ends_at: Type.String({ format: "date-time" }),
    members: Type.Array(Member),
  }),
});
