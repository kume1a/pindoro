import { createHash, randomBytes } from "node:crypto";
import type { FastifyRequest } from "fastify";
import { Type } from "typebox";

export const Problem = Type.Object({ message: Type.String() });

/** OpenAPI security for routes that take `Authorization: Bearer <token>`. */
export const bearer = { security: [{ bearer: [] }] };

export const bearerToken = (req: FastifyRequest): string | undefined =>
  /^Bearer (\S+)$/.exec(req.headers.authorization ?? "")?.[1];

/** Cloudflare's client address in production, the socket's elsewhere. */
export const clientIp = (req: FastifyRequest): string => {
  const forwarded = req.headers["cf-connecting-ip"];
  return typeof forwarded === "string" ? forwarded : req.ip;
};

/** Per-token limit for routes the app calls a few times a minute at most. */
export const perToken = {
  rateLimit: {
    max: 30,
    timeWindow: "1 minute",
    keyGenerator: (req: FastifyRequest): string => req.headers.authorization ?? req.ip,
  },
};

/** A random bearer token; the server keeps only `hashToken` of it. */
export const newToken = (): string => randomBytes(32).toString("base64url");

export const hashToken = (token: string): string =>
  createHash("sha256").update(token).digest("hex");
