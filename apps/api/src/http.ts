import { createHash, randomBytes } from "node:crypto";
import type { FastifyRequest } from "fastify";
import { Type } from "typebox";

export const Problem = Type.Object({ message: Type.String() });

/** OpenAPI security for routes that take `Authorization: Bearer <token>`. */
export const bearer = { security: [{ bearer: [] }] };

export const bearerToken = (req: FastifyRequest): string | undefined =>
  /^Bearer (\S+)$/.exec(req.headers.authorization ?? "")?.[1];

/** The first four groups of an IPv6 address: one home or server connection holds a whole /64. */
const ipv6Network = (ip: string): string => {
  const [head = "", tail] = ip.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const zeros = tail === undefined ? [] : Array(8 - left.length - right.length).fill("0");
  const groups = [...left, ...zeros, ...right].slice(0, 4);
  return `${groups.map((g) => Number.parseInt(g, 16).toString(16)).join(":")}::/64`;
};

/**
 * Cloudflare's client address in production, the socket's elsewhere. An IPv6 client counts as its
 * /64, so rotating addresses inside one network doesn't buy new rate-limit buckets.
 */
export const clientIp = (req: FastifyRequest): string => {
  const forwarded = req.headers["cf-connecting-ip"];
  const ip = typeof forwarded === "string" ? forwarded : req.ip;
  return ip.includes(":") && !ip.includes(".") ? ipv6Network(ip) : ip;
};

/** At most `max` requests per client address in `timeWindow` (e.g. "1 minute"). */
export const perIp = (
  max: number,
  timeWindow: string,
): { rateLimit: { max: number; timeWindow: string; keyGenerator: typeof clientIp } } => ({
  rateLimit: { max, timeWindow, keyGenerator: clientIp },
});

/** Per-token limit for routes the app calls a few times a minute at most. */
export const perToken = {
  rateLimit: {
    max: 30,
    timeWindow: "1 minute",
    keyGenerator: (req: FastifyRequest): string => req.headers.authorization ?? clientIp(req),
  },
};

/** A random bearer token; the server keeps only `hashToken` of it. */
export const newToken = (): string => randomBytes(32).toString("base64url");

export const hashToken = (token: string): string =>
  createHash("sha256").update(token).digest("hex");
