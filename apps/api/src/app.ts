import sensible from "@fastify/sensible";
import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import Fastify, { type FastifyInstance } from "fastify";
import type { Config } from "./config.ts";
import { createDb } from "./db/client.ts";
import { catalogRoutes } from "./modules/catalog/catalog.routes.ts";
import { healthRoutes } from "./modules/health/health.routes.ts";

export const buildApp = async (config: Config): Promise<FastifyInstance> => {
  const app = Fastify({
    logger: { level: config.LOG_LEVEL },
  }).withTypeProvider<TypeBoxTypeProvider>();
  const db = createDb(config.DATABASE_URL);
  app.addHook("onClose", async () => {
    await db.$client.end();
  });

  await app.register(sensible);
  await app.register(swagger, {
    openapi: { info: { title: "Pindoro API", version: "0.1.0" } },
  });
  if (config.NODE_ENV !== "production") await app.register(swaggerUi, { routePrefix: "/docs" });

  await app.register(healthRoutes, { db });
  await app.register(catalogRoutes, {
    packsDir: config.PACKS_DIR,
    packsPublicUrl: config.PACKS_PUBLIC_URL,
  });
  return app;
};
