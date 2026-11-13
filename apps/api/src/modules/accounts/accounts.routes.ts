import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyRequest } from "fastify";
import { Type } from "typebox";
import type { Db } from "../../db/client.ts";
import { bearer, bearerToken, Problem, perIp, perToken } from "../../http.ts";
import {
  isPassword,
  isRecoveryCode,
  isUsername,
  tidyRecoveryCode,
  tidyUsername,
} from "./accounts.rules.ts";
import {
  Backup,
  BackupAt,
  Credentials,
  PasswordChange,
  Reset,
  Session,
} from "./accounts.schemas.ts";
import {
  backupOf,
  changePassword,
  createAccount,
  deleteAccount,
  isLiveToken,
  resetPassword,
  saveBackup,
  signIn,
  signOut,
} from "./accounts.service.ts";

const MAX_BACKUP_BYTES = 5 * 1024 * 1024;

const isGzip = (body: Buffer): boolean => body[0] === 0x1f && body[1] === 0x8b;

export const accountsRoutes: FastifyPluginAsyncTypebox<{
  db: Db;
  now: () => Date;
  signupsPerHour: number;
}> = async (app, { db, now, signupsPerHour }) => {
  app.addContentTypeParser(
    "application/octet-stream",
    { parseAs: "buffer", bodyLimit: MAX_BACKUP_BYTES },
    (_req, body, done) => done(null, body),
  );

  const unknownToken = (): Error => app.httpErrors.unauthorized("unknown or missing account token");

  /** The bearer token; 401 when missing (whether it's live is up to each query). */
  const tokenOf = (req: FastifyRequest): string => {
    const token = bearerToken(req);
    if (token === undefined) throw unknownToken();
    return token;
  };

  /** Guesses at one username count wherever they come from; runs once the body is parsed. */
  const usernameGuesses = app.createRateLimit({
    max: 10,
    timeWindow: "15 minutes",
    keyGenerator: (req) =>
      `user:${tidyUsername((req.body as { username?: string } | undefined)?.username ?? "")}`,
  });
  // A second limit on top of the per-IP one, so it runs as a check of its own.
  const perUsername = async (req: FastifyRequest): Promise<void> => {
    const guesses = await usernameGuesses(req);
    if (!guesses.isAllowed && guesses.isExceeded) {
      throw app.httpErrors.tooManyRequests("too many tries for this username");
    }
  };

  const validPassword = (password: string): string => {
    if (!isPassword(password)) throw app.httpErrors.badRequest("invalid password");
    return password;
  };

  app.post(
    "/v1/accounts",
    {
      config: perIp(signupsPerHour, "1 hour"),
      schema: {
        tags: ["accounts"],
        body: Credentials,
        response: { 201: Session, 400: Problem, 409: Problem },
      },
    },
    async (req, reply) => {
      const username = tidyUsername(req.body.username);
      if (!isUsername(username)) throw app.httpErrors.badRequest("invalid username");
      const session = await createAccount(db, username, validPassword(req.body.password));
      if (!session) throw app.httpErrors.conflict("username taken");
      return reply.code(201).send(session);
    },
  );

  app.post(
    "/v1/sessions",
    {
      config: perIp(10, "1 minute"),
      preHandler: perUsername,
      schema: {
        tags: ["accounts"],
        body: Credentials,
        response: { 200: Session, 401: Problem },
      },
    },
    async (req) => {
      const session = await signIn(db, tidyUsername(req.body.username), req.body.password);
      if (!session) throw app.httpErrors.unauthorized("wrong username or password");
      return session;
    },
  );

  app.post(
    "/v1/accounts/reset",
    {
      config: perIp(10, "1 minute"),
      preHandler: perUsername,
      schema: {
        tags: ["accounts"],
        body: Reset,
        response: { 200: Session, 400: Problem, 401: Problem },
      },
    },
    async (req) => {
      const code = tidyRecoveryCode(req.body.recoveryCode);
      const password = validPassword(req.body.password);
      const session = isRecoveryCode(code)
        ? await resetPassword(db, tidyUsername(req.body.username), code, password)
        : undefined;
      if (!session) throw app.httpErrors.unauthorized("wrong username or recovery code");
      return session;
    },
  );

  app.put(
    "/v1/accounts/me/password",
    {
      config: perToken,
      schema: {
        tags: ["accounts"],
        ...bearer,
        body: PasswordChange,
        response: { 204: Type.Null(), 400: Problem, 401: Problem, 403: Problem },
      },
    },
    async (req, reply) => {
      const next = validPassword(req.body.newPassword);
      const result = await changePassword(db, tokenOf(req), req.body.password, next);
      if (result === "unknown") throw unknownToken();
      if (result === "wrong") throw app.httpErrors.forbidden("wrong password");
      return reply.code(204).send(null);
    },
  );

  app.delete(
    "/v1/sessions/me",
    {
      config: perToken,
      schema: { tags: ["accounts"], ...bearer, response: { 204: Type.Null(), 401: Problem } },
    },
    async (req, reply) => {
      if (!(await signOut(db, tokenOf(req)))) throw unknownToken();
      return reply.code(204).send(null);
    },
  );

  app.delete(
    "/v1/accounts/me",
    {
      config: perToken,
      schema: { tags: ["accounts"], ...bearer, response: { 204: Type.Null(), 401: Problem } },
    },
    async (req, reply) => {
      if (!(await deleteAccount(db, tokenOf(req)))) throw unknownToken();
      return reply.code(204).send(null);
    },
  );

  app.put(
    "/v1/accounts/me/backup",
    {
      config: perIp(30, "1 minute"),
      // A dead token is turned away before its body is read.
      preParsing: async (req) => {
        if (!(await isLiveToken(db, tokenOf(req)))) throw unknownToken();
      },
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
      if (!Buffer.isBuffer(req.body) || !isGzip(req.body)) {
        throw app.httpErrors.badRequest("backup must be gzip");
      }
      const at = await saveBackup(db, tokenOf(req), req.body, now());
      if (!at) throw unknownToken();
      return { backupAt: at.toISOString() };
    },
  );

  app.get(
    "/v1/accounts/me/backup",
    {
      config: perIp(30, "1 minute"),
      schema: {
        tags: ["accounts"],
        ...bearer,
        response: {
          200: {
            description: "The backup",
            content: { "application/octet-stream": { schema: Backup } },
          },
          401: Problem,
          404: Problem,
        },
      },
    },
    async (req, reply) => {
      const backup = await backupOf(db, tokenOf(req));
      if (backup === undefined) throw unknownToken();
      if (backup === null) throw app.httpErrors.notFound("no backup yet");
      return reply.type("application/octet-stream").send(backup);
    },
  );
};
