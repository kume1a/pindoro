import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyRequest } from "fastify";
import { Type } from "typebox";
import type { Db } from "../../db/client.ts";
import { bearer, bearerToken, Problem, perIp, perToken } from "../../http.ts";
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

export const leaguesRoutes: FastifyPluginAsyncTypebox<{
  db: Db;
  now: () => Date;
  signupsPerHour: number;
}> = async (app, { db, now, signupsPerHour }) => {
  const unknownPlayer = (): Error => app.httpErrors.unauthorized("unknown or missing player token");

  const me = async (req: FastifyRequest): Promise<{ id: string; name: string }> => {
    const token = bearerToken(req);
    const found = token === undefined ? undefined : await playerByToken(db, token);
    if (!found) throw unknownPlayer();
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
      config: perIp(signupsPerHour, "1 hour"),
      schema: { tags: ["leagues"], body: NameBody, response: { 201: NewPlayer, 400: Problem } },
    },
    async (req, reply) => reply.code(201).send(await createPlayer(db, validName(req.body.name))),
  );

  app.patch(
    "/v1/players/me",
    {
      config: perToken,
      schema: {
        tags: ["leagues"],
        ...bearer,
        body: NameBody,
        response: { 200: Player, 400: Problem, 401: Problem },
      },
    },
    async (req) => {
      const player = await me(req);
      const renamed = await renamePlayer(db, player.id, validName(req.body.name));
      if (!renamed) throw unknownPlayer();
      return renamed;
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
      config: perToken,
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
      const stillPlaying = await syncXp(db, player, req.body.week, req.body.xp, at);
      if (!stillPlaying) throw unknownPlayer();
      return standing(db, player, at);
    },
  );
};
