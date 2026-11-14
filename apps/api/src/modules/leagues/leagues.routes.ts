import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { Db } from "../../db/client.ts";
import { bearer, bearerToken, Problem, perToken } from "../../http.ts";
import { Standing, XpBody } from "./leagues.schemas.ts";
import { accountByToken, standing, syncXp } from "./leagues.service.ts";

export const leaguesRoutes: FastifyPluginAsyncTypebox<{
  db: Db;
  now: () => Date;
}> = async (app, { db, now }) => {
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
      const token = bearerToken(req);
      const me = token === undefined ? undefined : await accountByToken(db, token);
      const at = now();
      if (!me || !(await syncXp(db, me, req.body.week, req.body.xp, at))) {
        throw app.httpErrors.unauthorized("unknown or missing account token");
      }
      return standing(db, me, at);
    },
  );
};
