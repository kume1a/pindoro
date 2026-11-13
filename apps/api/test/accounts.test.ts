import { gzipSync } from "node:zlib";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import postgres from "postgres";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { runMigrations } from "../src/db/migrate.ts";

const DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro_test";

const noon = new Date("2026-11-13T12:00:00Z");

type Session = { token: string; account: { username: string }; backupAt: string | null };

describe("accounts", () => {
  let app: FastifyInstance;
  const sql = postgres(DATABASE_URL, { max: 1, onnotice: () => {} });

  beforeAll(async () => {
    await runMigrations(DATABASE_URL);
    app = await buildApp(
      loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", DATABASE_URL, SIGNUP_LIMIT: "1000" }),
      { now: () => noon },
    );
  });

  beforeEach(async () => {
    await sql`truncate account`;
  });

  afterAll(async () => {
    await app?.close();
    await sql.end();
  });

  const post = (
    url: string,
    username: string,
    password = "correct horse",
  ): Promise<LightMyRequestResponse> =>
    app.inject({ method: "POST", url, payload: { username, password } });

  const create = async (username: string): Promise<Session> => {
    const res = await post("/v1/accounts", username);
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const upload = (token: string | undefined, body: Buffer): Promise<LightMyRequestResponse> =>
    app.inject({
      method: "PUT",
      url: "/v1/accounts/me/backup",
      headers: {
        "content-type": "application/octet-stream",
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      payload: body,
    });

  const download = (token: string): Promise<LightMyRequestResponse> =>
    app.inject({
      method: "GET",
      url: "/v1/accounts/me/backup",
      headers: { authorization: `Bearer ${token}` },
    });

  it("creates an account with a tidied username, a token and hashes only", async () => {
    const session = await create("  Nino.K ");
    expect(session.account).toEqual({ username: "nino.k" });
    expect(session.backupAt).toBeNull();
    const [row] = await sql`select password_hash, token_hash from account`;
    expect(row?.password_hash).not.toContain("correct horse");
    expect(row?.token_hash).not.toBe(session.token);
  });

  it("refuses a taken username, in any case", async () => {
    await create("nino");
    expect((await post("/v1/accounts", "NINO")).statusCode).toBe(409);
  });

  it("refuses bad usernames and short passwords", async () => {
    expect((await post("/v1/accounts", "ab")).statusCode).toBe(400);
    expect((await post("/v1/accounts", "has space")).statusCode).toBe(400);
    expect((await post("/v1/accounts", "nino", "short")).statusCode).toBe(400);
  });

  it("signs in only with the right password", async () => {
    await create("nino");
    expect((await post("/v1/sessions", "nino", "wrong password")).statusCode).toBe(401);
    expect((await post("/v1/sessions", "nobody")).statusCode).toBe(401);
    const res = await post("/v1/sessions", "Nino");
    expect(res.statusCode).toBe(200);
    expect(res.json().account).toEqual({ username: "nino" });
  });

  it("signs the old phone out when another one signs in", async () => {
    const first = await create("nino");
    const second: Session = (await post("/v1/sessions", "nino")).json();
    const backup = gzipSync("sqlite");
    expect((await upload(first.token, backup)).statusCode).toBe(401);
    expect((await upload(second.token, backup)).statusCode).toBe(200);
  });

  it("keeps the last backup and reports when it was made", async () => {
    const { token } = await create("nino");
    expect((await download(token)).statusCode).toBe(404);
    const backup = gzipSync("pindoro progress");
    const saved = await upload(token, backup);
    expect(saved.json()).toEqual({ backupAt: noon.toISOString() });
    const res = await download(token);
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toBe("application/octet-stream");
    expect(res.rawPayload.equals(backup)).toBe(true);
    const session: Session = (await post("/v1/sessions", "nino")).json();
    expect(session.backupAt).toBe(noon.toISOString());
  });

  it("refuses a backup without a token, that isn't gzip, or that is too big", async () => {
    const { token } = await create("nino");
    expect((await upload(undefined, gzipSync("x"))).statusCode).toBe(401);
    expect((await upload(token, Buffer.from("plain"))).statusCode).toBe(400);
    expect((await upload(token, Buffer.alloc(11 * 1024 * 1024, 0x1f))).statusCode).toBe(413);
  });
});
