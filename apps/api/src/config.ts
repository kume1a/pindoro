import { type Static, Type } from "typebox";
import { Value } from "typebox/value";

const Env = Type.Object({
  NODE_ENV: Type.Union(
    [Type.Literal("development"), Type.Literal("test"), Type.Literal("production")],
    {
      default: "development",
    },
  ),
  HOST: Type.String({ default: "0.0.0.0" }),
  PORT: Type.Integer({ minimum: 1, maximum: 65535, default: 3000 }),
  LOG_LEVEL: Type.Union(
    ["fatal", "error", "warn", "info", "debug", "trace", "silent"].map((l) => Type.Literal(l)),
    { default: "info" },
  ),
  DATABASE_URL: Type.String({
    pattern: "^postgres(ql)?://",
    default: "postgres://pindoro:pindoro@localhost:5433/pindoro",
  }),
  PACKS_DIR: Type.String({ minLength: 1, default: "../../infra/packs" }),
  PACKS_PUBLIC_URL: Type.String({ pattern: "^https?://", default: "http://localhost:8080" }),
  // New league players, and new accounts, per client IP per hour.
  SIGNUP_LIMIT: Type.Integer({ minimum: 1, default: 10 }),
  // The newest sideload build (pubspec.yaml's +N) and its APK link; 0 lists none.
  APP_BUILD: Type.Integer({ minimum: 0, default: 0 }),
  APP_URL: Type.String({ pattern: "^(https?://.+)?$", default: "" }),
});

export type Config = Static<typeof Env>;

// Fail fast at startup: defaults -> string coercion -> strip unknown keys -> validate.
export const loadConfig = (env: Record<string, string | undefined> = process.env): Config => {
  const value = Value.Clean(Env, Value.Convert(Env, Value.Default(Env, { ...env })));
  if (Value.Check(Env, value)) return value;
  const problems = Value.Errors(Env, value).map((e) => `${e.instancePath || "/"} ${e.message}`);
  throw new Error(`Invalid environment:\n  ${problems.join("\n  ")}`);
};
