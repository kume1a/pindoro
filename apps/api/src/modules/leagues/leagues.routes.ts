import rateLimit from "@fastify/rate-limit";
import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyRequest } from "fastify";
import { Type } from "typebox";
import type { Db } from "../../db/client.ts";
import { isLeagueName, leagueName } from "./leagues.rules.ts";
import { NameBody, NewPlayer, Player, Standing, XpBody } from "./leagues.schemas.ts";
import {
  createPlayer,
  forgetPlayer,
  playerByToken,
  renamePlayer,
  standing,
  syncXp,
} from "./leagues.service.ts";

const Problem = Type.Object({ message: Type.String() });
const bearer = { security: [{ bearer: [] }] };

/** Renames and syncs per player token; the app syncs a few times a minute at most. */
const perPlayer = {
  rateLimit: {
    max: 30,
    timeWindow: "1 minute",
    keyGenerator: (req: FastifyRequest): string => req.headers.authorization ?? req.ip,
  },
};

/** Cloudflare's client address in production, the socket's elsewhere. */
const clientIp = (req: FastifyRequest): string => {
  const forwarded = req.headers["cf-connecting-ip"];
  return typeof forwarded === "string" ? forwarded : req.ip;
};

export const leaguesRoutes: FastifyPluginAsyncTypebox<{
  db: Db;
  now: () => Date;
  signupsPerHour: number;
}> = async (app, { db, now, signupsPerHour }) => {
  await app.register(rateLimit, { global: false });

  const me = async (req: FastifyRequest): Promise<{ id: string; name: string }> => {
    const token = /^Bearer (\S+)$/.exec(req.headers.authorization ?? "")?.[1];
    const found = token === undefined ? undefined : await playerByToken(db, token);
    if (!found) throw app.httpErrors.unauthorized("unknown or missing player token");
    return found;
  };

  const validName = (raw: string): string => {
    const name = leagueName(raw);
    if (!isLeagueName(name)) throw app.httpErrors.badRequest("invalid league name");
    return name;
  };

  app.post(
    "/v1/players",
    {
      config: { rateLimit: { max: signupsPerHour, timeWindow: "1 hour", keyGenerator: clientIp } },
      schema: { tags: ["leagues"], body: NameBody, response: { 201: NewPlayer, 400: Problem } },
    },
    async (req, reply) => reply.code(201).send(await createPlayer(db, validName(req.body.name))),
  );

  app.patch(
    "/v1/players/me",
    {
      config: perPlayer,
      schema: {
        tags: ["leagues"],
        ...bearer,
        body: NameBody,
        response: { 200: Player, 400: Problem, 401: Problem },
      },
    },
    async (req) => {
      const player = await me(req);
      return renamePlayer(db, player.id, validName(req.body.name));
    },
  );

  app.delete(
    "/v1/players/me",
    {
      schema: { tags: ["leagues"], ...bearer, response: { 204: Type.Null(), 401: Problem } },
    },
    async (req, reply) => {
      await forgetPlayer(db, (await me(req)).id, now());
      return reply.code(204).send(null);
    },
  );

  app.put(
    "/v1/league/me",
    {
      config: perPlayer,
      schema: {
        tags: ["leagues"],
        ...bearer,
        body: XpBody,
        response: { 200: Standing, 401: Problem },
      },
    },
    async (req) => {
      const player = await me(req);
      const at = now();
      await syncXp(db, player, req.body.week, req.body.xp, at);
      return standing(db, player, at);
    },
  );
};
