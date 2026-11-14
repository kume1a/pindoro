import { Type } from "typebox";
import { LEAGUE } from "./leagues.rules.ts";

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

// The account's league this week; `members` (named by username) is empty until it earns XP this
// week.
export const Standing = Type.Object({
  league: Type.Object({
    tier: Type.Integer({ minimum: 0, maximum: LEAGUE.tiers - 1 }),
    week: Type.String({ format: "date" }),
    ends_at: Type.String({ format: "date-time" }),
    members: Type.Array(Member),
  }),
});
