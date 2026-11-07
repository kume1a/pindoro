import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import { sql } from "drizzle-orm";
import { Type } from "typebox";
import type { Db } from "../../db/client.ts";

const Health = Type.Object({
  status: Type.Union([Type.Literal("ok"), Type.Literal("unavailable")]),
  postgis: Type.Optional(Type.String()),
});

export const healthRoutes: FastifyPluginAsyncTypebox<{ db: Db }> = async (app, { db }) => {
  app.get(
    "/health",
    { schema: { tags: ["ops"], response: { 200: Health, 503: Health } } },
    async (req, reply) => {
      try {
        const [row] = await db.execute<{ postgis: string }>(
          sql`select postgis_lib_version() as postgis`,
        );
        return { status: "ok" as const, postgis: row?.postgis };
      } catch (err) {
        req.log.error({ err }, "database health check failed");
        return reply.code(503).send({ status: "unavailable" });
      }
    },
  );
};
