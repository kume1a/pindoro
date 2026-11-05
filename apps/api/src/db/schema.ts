import {
  bigint,
  customType,
  doublePrecision,
  index,
  pgTable,
  primaryKey,
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
    kind: text({ enum: ["district", "neighbourhood"] }).notNull(),
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
