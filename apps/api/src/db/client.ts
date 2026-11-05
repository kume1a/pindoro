import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema.ts";

export const createDb = (url: string): ReturnType<typeof drizzle<typeof schema>> =>
  drizzle(postgres(url, { onnotice: () => {} }), { schema, casing: "snake_case" });

export type Db = ReturnType<typeof createDb>;
