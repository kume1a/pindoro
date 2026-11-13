import { gzipSync } from "node:zlib";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import postgres from "postgres";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { runMigrations } from "../src/db/migrate.ts";
import { isRecoveryCode } from "../src/modules/accounts/accounts.rules.ts";

const DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro_test";

const noon = new Date("2026-11-13T12:00:00Z");
const PASSWORD = "correct horse";

type Session = {
  token: string;
  account: { username: string };
  backupAt: string | null;
  recoveryCode?: string;
};

describe("accounts", () => {
  let app: FastifyInstance;
  const sql = postgres(DATABASE_URL, { max: 1, onnotice: () => {} });

  beforeAll(async () => {
    await runMigrations(DATABASE_URL);
  });

  // A fresh app per test: the rate limits count in memory.
  beforeEach(async () => {
    await sql`truncate account`;
    app = await buildApp(
      loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", DATABASE_URL, SIGNUP_LIMIT: "1000" }),
      { now: () => noon },
    );
  });

  afterEach(async () => {
    await app.close();
  });

  afterAll(async () => {
    await sql.end();
  });

  const post = (
    url: string,
    payload: Record<string, string>,
    ip = "203.0.113.1",
  ): Promise<LightMyRequestResponse> =>
    app.inject({ method: "POST", url, payload, headers: { "cf-connecting-ip": ip } });

  const create = async (username: string): Promise<Session> => {
    const res = await post("/v1/accounts", { username, password: PASSWORD });
    expect(res.statusCode).toBe(201);
    return res.json();
  };

  const signIn = (username: string, password = PASSWORD): Promise<LightMyRequestResponse> =>
    post("/v1/sessions", { username, password });

  const withToken = (
    method: "GET" | "PUT" | "DELETE",
    url: string,
    token: string | undefined,
    payload?: Buffer | Record<string, string>,
  ): Promise<LightMyRequestResponse> =>
    app.inject({
      method,
      url,
      headers: {
        ...(Buffer.isBuffer(payload) ? { "content-type": "application/octet-stream" } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      ...(payload ? { payload } : {}),
    });

  const upload = (token: string | undefined, body: Buffer): Promise<LightMyRequestResponse> =>
    withToken("PUT", "/v1/accounts/me/backup", token, body);

  const download = (token: string): Promise<LightMyRequestResponse> =>
    withToken("GET", "/v1/accounts/me/backup", token);

  it("creates an account with a tidied username, a recovery code and hashes only", async () => {
    const session = await create("  Nino.K ");
    expect(session.account).toEqual({ username: "nino.k" });
    expect(session.backupAt).toBeNull();
    expect(isRecoveryCode(session.recoveryCode ?? "")).toBe(true);
    const [row] = await sql`select password_hash, token_hash, recovery_hash from account`;
    expect(row?.password_hash).not.toContain(PASSWORD);
    expect(row?.token_hash).not.toBe(session.token);
    expect(row?.recovery_hash).not.toBe(session.recoveryCode);
  });

  it("refuses a taken username, in any case", async () => {
    await create("nino");
    const res = await post("/v1/accounts", { username: "NINO", password: PASSWORD });
    expect(res.statusCode).toBe(409);
  });

  it("refuses bad usernames and passwords by the shared rules", async () => {
    const status = async (username: string, password: string): Promise<number> =>
      (await post("/v1/accounts", { username, password })).statusCode;
    expect(await status("ab", PASSWORD)).toBe(400);
    expect(await status("has space", PASSWORD)).toBe(400);
    expect(await status("nino", "short")).toBe(400);
    expect(await status("nino", "🔑🔑🔑🔑🔑🔑")).toBe(400);
  });

  it("signs in only with the right password, without saying which part is wrong", async () => {
    await create("nino");
    expect((await signIn("nino", "wrong password")).statusCode).toBe(401);
    expect((await signIn("nobody")).statusCode).toBe(401);
    const res = await signIn("Nino");
    expect(res.statusCode).toBe(200);
    expect(res.json().account).toEqual({ username: "nino" });
    expect(res.json().recoveryCode).toBeUndefined();
  });

  it("counts sign-in guesses per username, from any address", async () => {
    await create("nino");
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      statuses.push(
        (await post("/v1/sessions", { username: "nino", password: "x" }, `198.51.100.${i}`))
          .statusCode,
      );
    }
    expect(statuses.slice(0, 10).every((s) => s === 401)).toBe(true);
    expect(statuses[10]).toBe(429);
    expect((await signIn("someone.else")).statusCode).toBe(401);
  });

  it("signs the old phone out when another one signs in", async () => {
    const first = await create("nino");
    const second: Session = (await signIn("nino")).json();
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
    const session: Session = (await signIn("nino")).json();
    expect(session.backupAt).toBe(noon.toISOString());
  });

  it("takes a backup up to 5 MiB, refusing it without a token, unzipped or bigger", async () => {
    const { token } = await create("nino");
    const big = Buffer.alloc(5 * 1024 * 1024 - 1, 0);
    big[0] = 0x1f;
    big[1] = 0x8b;
    expect((await upload(token, big)).statusCode).toBe(200);
    expect((await upload(undefined, gzipSync("x"))).statusCode).toBe(401);
    expect((await upload("made-up", Buffer.alloc(6 * 1024 * 1024))).statusCode).toBe(401);
    expect((await upload(token, Buffer.from("plain"))).statusCode).toBe(400);
    expect((await upload(token, Buffer.alloc(6 * 1024 * 1024, 0x1f))).statusCode).toBe(413);
  });

  it("resets a forgotten password with the recovery code, which then changes", async () => {
    const created = await create("nino");
    const reset = (recoveryCode: string): Promise<LightMyRequestResponse> =>
      post("/v1/accounts/reset", { username: "nino", recoveryCode, password: "new password" });
    expect((await reset("abcd-efgh-jkmn-pqrs")).statusCode).toBe(401);
    const res = await reset(` ${created.recoveryCode?.toUpperCase()} `);
    expect(res.statusCode).toBe(200);
    const session: Session = res.json();
    expect(session.recoveryCode).not.toBe(created.recoveryCode);
    expect((await reset(created.recoveryCode ?? "")).statusCode).toBe(401);
    expect((await signIn("nino")).statusCode).toBe(401);
    expect((await signIn("nino", "new password")).statusCode).toBe(200);
    expect((await upload(created.token, gzipSync("x"))).statusCode).toBe(401);
  });

  it("changes the password with the current one", async () => {
    const { token } = await create("nino");
    const change = (password: string, newPassword: string): Promise<LightMyRequestResponse> =>
      withToken("PUT", "/v1/accounts/me/password", token, { password, newPassword });
    expect((await change("wrong password", "new password")).statusCode).toBe(403);
    expect((await change(PASSWORD, "short")).statusCode).toBe(400);
    expect((await change(PASSWORD, "new password")).statusCode).toBe(204);
    expect((await signIn("nino", "new password")).statusCode).toBe(200);
  });

  it("signs out: the token dies, the account stays", async () => {
    const { token } = await create("nino");
    expect((await withToken("DELETE", "/v1/sessions/me", token)).statusCode).toBe(204);
    expect((await withToken("DELETE", "/v1/sessions/me", token)).statusCode).toBe(401);
    expect((await download(token)).statusCode).toBe(401);
    expect((await signIn("nino")).statusCode).toBe(200);
  });

  it("deletes the account and its backup", async () => {
    const { token } = await create("nino");
    await upload(token, gzipSync("x"));
    expect((await withToken("DELETE", "/v1/accounts/me", token)).statusCode).toBe(204);
    expect(await sql`select 1 from account`).toHaveLength(0);
    expect((await withToken("DELETE", "/v1/accounts/me", token)).statusCode).toBe(401);
    expect((await signIn("nino")).statusCode).toBe(401);
  });
});
