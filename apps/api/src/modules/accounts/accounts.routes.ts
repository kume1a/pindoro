import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyRequest } from "fastify";
import type { Db } from "../../db/client.ts";
import { bearer, bearerToken, clientIp, Problem, perToken } from "../../http.ts";
import { Backup, BackupAt, Credentials, Session, USERNAME } from "./accounts.schemas.ts";
import {
  accountIdByToken,
  backupOf,
  createAccount,
  saveBackup,
  signIn,
} from "./accounts.service.ts";

const BACKUP_LIMIT = 10 * 1024 * 1024;

const tidyUsername = (raw: string): string => raw.trim().toLowerCase();

const isGzip = (body: Buffer): boolean => body[0] === 0x1f && body[1] === 0x8b;

export const accountsRoutes: FastifyPluginAsyncTypebox<{
  db: Db;
  now: () => Date;
  signupsPerHour: number;
}> = async (app, { db, now, signupsPerHour }) => {
  app.addContentTypeParser(
    "application/octet-stream",
    { parseAs: "buffer", bodyLimit: BACKUP_LIMIT },
    (_req, body, done) => done(null, body),
  );

  const me = async (req: FastifyRequest): Promise<string> => {
    const token = bearerToken(req);
    const id = token === undefined ? undefined : await accountIdByToken(db, token);
    if (!id) throw app.httpErrors.unauthorized("unknown or missing account token");
    return id;
  };

  app.post(
    "/v1/accounts",
    {
      config: { rateLimit: { max: signupsPerHour, timeWindow: "1 hour", keyGenerator: clientIp } },
      schema: {
        tags: ["accounts"],
        body: Credentials,
        response: { 201: Session, 400: Problem, 409: Problem },
      },
    },
    async (req, reply) => {
      const username = tidyUsername(req.body.username);
      if (!USERNAME.test(username)) throw app.httpErrors.badRequest("invalid username");
      const session = await createAccount(db, username, req.body.password);
      if (!session) throw app.httpErrors.conflict("username taken");
      return reply.code(201).send(session);
    },
  );

  app.post(
    "/v1/sessions",
    {
      config: { rateLimit: { max: 10, timeWindow: "1 minute", keyGenerator: clientIp } },
      schema: {
        tags: ["accounts"],
        body: Credentials,
        response: { 200: Session, 400: Problem, 401: Problem },
      },
    },
    async (req) => {
      const session = await signIn(db, tidyUsername(req.body.username), req.body.password);
      if (!session) throw app.httpErrors.unauthorized("wrong username or password");
      return session;
    },
  );

  app.put(
    "/v1/accounts/me/backup",
    {
      config: perToken,
      // ponytail: AJV can't check a Buffer; the handler checks the gzip header instead.
      validatorCompiler: () => (): boolean => true,
      schema: {
        tags: ["accounts"],
        ...bearer,
        consumes: ["application/octet-stream"],
        body: Backup,
        response: { 200: BackupAt, 400: Problem, 401: Problem, 413: Problem },
      },
    },
    async (req) => {
      const id = await me(req);
      if (!Buffer.isBuffer(req.body) || !isGzip(req.body)) {
        throw app.httpErrors.badRequest("backup must be gzip");
      }
      const at = now();
      await saveBackup(db, id, req.body, at);
      return { backupAt: at.toISOString() };
    },
  );

  app.get(
    "/v1/accounts/me/backup",
    {
      config: perToken,
      schema: {
        tags: ["accounts"],
        ...bearer,
        produces: ["application/octet-stream"],
        response: { 200: Backup, 401: Problem, 404: Problem },
      },
    },
    async (req, reply) => {
      const backup = await backupOf(db, await me(req));
      if (!backup) throw app.httpErrors.notFound("no backup yet");
      return reply.type("application/octet-stream").send(backup);
    },
  );
};
