import rateLimit from "@fastify/rate-limit";
import sensible from "@fastify/sensible";
import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import type { Config } from "./config.ts";
import { createDb } from "./db/client.ts";
import { accountsRoutes } from "./modules/accounts/accounts.routes.ts";
import { catalogRoutes } from "./modules/catalog/catalog.routes.ts";
import { healthRoutes } from "./modules/health/health.routes.ts";
import { leaguesRoutes } from "./modules/leagues/leagues.routes.ts";

/** `now` is the clock leagues and backups read (tests move it across weeks). */
export const buildApp = async (
  config: Config,
  { now = (): Date => new Date() }: { now?: () => Date } = {},
): Promise<FastifyInstance> => {
  const app = Fastify({
    logger: { level: config.LOG_LEVEL },
  }).withTypeProvider<TypeBoxTypeProvider>();
  const db = createDb(config.DATABASE_URL);
  app.addHook("onClose", async () => {
    await db.$client.end();
  });
  // A failed query's message carries its parameters (password hashes, backups): server errors log
  // only their cause and answer a plain message.
  app.setErrorHandler((err: FastifyError, req, reply) => {
    if ((err.statusCode ?? 500) < 500) return reply.send(err);
    const cause = err.cause instanceof Error ? err.cause.message : undefined;
    req.log.error({ code: err.code, cause }, "request failed");
    return reply.code(500).send({ message: "internal server error" });
  });

  await app.register(sensible);
  // Routes opt in with `config.rateLimit`.
  await app.register(rateLimit, { global: false });
  await app.register(swagger, {
    openapi: {
      info: { title: "Pindoro API", version: "0.1.0" },
      components: { securitySchemes: { bearer: { type: "http", scheme: "bearer" } } },
    },
  });
  if (config.NODE_ENV !== "production") await app.register(swaggerUi, { routePrefix: "/docs" });

  await app.register(healthRoutes, { db });
  await app.register(catalogRoutes, {
    packsDir: config.PACKS_DIR,
    packsPublicUrl: config.PACKS_PUBLIC_URL,
    app:
      config.APP_BUILD > 0 && config.APP_URL
        ? { build: config.APP_BUILD, url: config.APP_URL }
        : undefined,
  });
  await app.register(leaguesRoutes, { db, now, signupsPerHour: config.SIGNUP_LIMIT });
  await app.register(accountsRoutes, { db, now, signupsPerHour: config.SIGNUP_LIMIT });
  return app;
};
