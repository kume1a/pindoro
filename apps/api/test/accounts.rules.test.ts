import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  isPassword,
  isRecoveryCode,
  isUsername,
  newRecoveryCode,
  tidyRecoveryCode,
  tidyUsername,
} from "../src/modules/accounts/accounts.rules.ts";

type Vectors = {
  username: { raw: string; username: string; valid: boolean }[];
  password: { password: string; valid: boolean }[];
  recoveryCode: { raw: string; code: string; valid: boolean }[];
};

const vectors: Vectors = JSON.parse(
  readFileSync(new URL("../../../shared/fixtures/account_vectors.json", import.meta.url), "utf8"),
);

describe("usernames", () => {
  it.each(vectors.username)('"$raw"', (v) => {
    const username = tidyUsername(v.raw);
    expect(username).toBe(v.username);
    expect(isUsername(username)).toBe(v.valid);
  });
});

describe("passwords", () => {
  it.each(vectors.password)('"$password"', (v) => {
    expect(isPassword(v.password)).toBe(v.valid);
  });
});

describe("recovery codes", () => {
  it.each(vectors.recoveryCode)('"$raw"', (v) => {
    const code = tidyRecoveryCode(v.raw);
    expect(code).toBe(v.code);
    expect(isRecoveryCode(code)).toBe(v.valid);
  });

  it("makes valid, different codes", () => {
    const codes = Array.from({ length: 20 }, newRecoveryCode);
    expect(codes.every(isRecoveryCode)).toBe(true);
    expect(new Set(codes).size).toBe(codes.length);
  });
});
