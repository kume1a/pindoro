import {
  bigint,
  customType,
  date,
  doublePrecision,
  index,
  integer,
  pgTable,
  primaryKey,
  smallint,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

// PostGIS geometry in WGS84. Values travel as EWKB hex strings; use ST_* functions via sql`` to
// read or build them (e.g. sql`ST_AsGeoJSON(${street.geom})`).
const geometry = customType<{
  data: string;
  driverData: string;
  config: { type: "MultiPolygon" | "MultiLineString" };
}>({
  dataType: (config) => `geometry(${config?.type ?? "Geometry"}, 4326)`,
});

const osmRelationId = (): ReturnType<typeof bigint> => bigint({ mode: "number" });

export const city = pgTable("city", {
  id: text().primaryKey(),
  nameKa: text().notNull(),
  nameEn: text().notNull(),
  osmRelationId: osmRelationId().notNull(),
  areaM2: doublePrecision("area_m2").notNull(),
  boundary: geometry({ type: "MultiPolygon" }).notNull(),
});

export const district = pgTable(
  "district",
  {
    id: text().primaryKey(),
    cityId: text()
      .notNull()
      .references(() => city.id),
    kind: text({ enum: ["district", "quarter", "neighbourhood"] }).notNull(),
    osmRelationId: osmRelationId(),
    nameKa: text().notNull(),
    nameEn: text(),
    areaM2: doublePrecision("area_m2").notNull(),
    boundary: geometry({ type: "MultiPolygon" }).notNull(),
  },
  (t) => [index().using("gist", t.boundary)],
);

export const street = pgTable(
  "street",
  {
    id: uuid().primaryKey(),
    cityId: text()
      .notNull()
      .references(() => city.id),
    nameKa: text().notNull(),
    nameEn: text(),
    roadClass: text().notNull(),
    difficulty: text({ enum: ["easy", "medium", "hard", "expert"] }).notNull(),
    lengthM: doublePrecision().notNull(),
    geom: geometry({ type: "MultiLineString" }).notNull(),
  },
  (t) => [index().using("gist", t.geom)],
);

export const streetDistrict = pgTable(
  "street_district",
  {
    streetId: uuid()
      .notNull()
      .references(() => street.id),
    districtId: text()
      .notNull()
      .references(() => district.id),
    lengthM: doublePrecision().notNull(),
    share: doublePrecision().notNull(),
  },
  (t) => [primaryKey({ columns: [t.streetId, t.districtId] })],
);

export const pack = pgTable(
  "pack",
  {
    cityId: text()
      .notNull()
      .references(() => city.id),
    version: text().notNull(),
    file: text().notNull(),
    sha256: text().notNull(),
    size: bigint({ mode: "number" }).notNull(),
    osmTimestamp: timestamp({ withTimezone: true }).notNull(),
    publishedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.cityId, t.version] })],
);

// An anonymous league player: the app holds the token, the server only its sha256.
export const player = pgTable("player", {
  id: uuid().primaryKey().defaultRandom(),
  tokenHash: text().notNull().unique(),
  name: text().notNull(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

// One league of up to 30 players for a week (its Monday in Tbilisi) and tier (0 Alley … 5 Highway).
export const league = pgTable(
  "league",
  {
    id: uuid().primaryKey().defaultRandom(),
    week: date({ mode: "string" }).notNull(),
    tier: smallint().notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index().on(t.week, t.tier)],
);

// A player's place in one week's league: at most one league a week.
export const leagueMember = pgTable(
  "league_member",
  {
    playerId: uuid()
      .notNull()
      .references(() => player.id, { onDelete: "cascade" }),
    week: date({ mode: "string" }).notNull(),
    leagueId: uuid()
      .notNull()
      .references(() => league.id, { onDelete: "cascade" }),
    xp: integer().notNull(),
    joinedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.playerId, t.week] }), index().on(t.leagueId)],
);
