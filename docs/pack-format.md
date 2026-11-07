# City pack format (v2)

A city pack is a read-only SQLite database built by `pipeline` from OpenStreetMap data and
downloaded by the app. Packs are immutable: a new build gets a new `version` and a new file name.

v2 (2026-11) adds the `quarter` area kind (OSM `place=quarter`, which v1 stored as
`neighbourhood`) and puts area centres at the pole of inaccessibility. The app downloads only the
format it supports; v1 packs already on a phone still open.

## Files

```
<PACKS_DIR>/
  catalog.json                                  # all cities, rewritten atomically by `publish`
  tbilisi/
    manifest.json                               # current pack of the city
    tbilisi-20261105T221700Z.sqlite.gz          # gzipped pack, immutable, cached forever
```

`version` is the UTC build time formatted `YYYYMMDDTHHMMSSZ`, so versions sort lexically.

### manifest.json

```json
{
  "format_version": 2,
  "city": "tbilisi",
  "name_ka": "თბილისი",
  "name_en": "Tbilisi",
  "version": "20261105T221700Z",
  "file": "tbilisi-20261105T221700Z.sqlite.gz",
  "sha256": "<hex sha256 of the .gz file>",
  "size": 1234567,
  "osm_timestamp": "2026-11-04T20:21:42Z",
  "generated_at": "2026-11-05T22:17:00Z",
  "bbox": { "min_lat": 41.57, "min_lon": 44.59, "max_lat": 41.84, "max_lon": 45.02 }
}
```

`sha256` and `size` describe the `.gz` file the client downloads; the client verifies them before
decompressing. `bbox` is the city's bounding box, so the app can find the city the player is in.

### catalog.json

```json
{
  "format_version": 1,
  "generated_at": "2026-11-05T22:17:05Z",
  "cities": [{ "...manifest fields": "...", "url": "tbilisi/tbilisi-20261105T221700Z.sqlite.gz" }]
}
```

`url` is relative to the packs host; the API catalog (`/v1/catalog`) gives the app absolute URLs.

## Encodings

- **polyline6** – Google polyline algorithm with 1e6 precision, `(lat, lon)` order, rounding half
  away from zero (`@pindoro/geo` and `pindoro_core` share golden vectors).
- **multiline6** – JSON array of polyline6 strings, one per line part: `["_izlhA~rl…", "…"]`.
- **multipolygon6** – JSON array of polygons; each polygon is an array of closed rings (first outer,
  then holes), each ring a polyline6 string: `[["outer", "hole"], ["outer"]]`.

All coordinates are WGS84. Lengths and areas are metres / square metres measured in the city's UTM
zone. Street geometry is simplified to 3 m.

## Schema

`PRAGMA user_version = 2` equals `format_version`.

```sql
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
-- keys: format_version, city_id, version, scope ('full' | 'fixture'), osm_timestamp,
--       generated_at, attribution ('© OpenStreetMap contributors'), license ('ODbL-1.0')

CREATE TABLE city (
  id              TEXT PRIMARY KEY,      -- 'tbilisi'
  name_ka         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  osm_relation_id INTEGER NOT NULL,
  center_lat      REAL NOT NULL,
  center_lon      REAL NOT NULL,
  min_lat         REAL NOT NULL,
  min_lon         REAL NOT NULL,
  max_lat         REAL NOT NULL,
  max_lon         REAL NOT NULL,
  area_m2         REAL NOT NULL,
  boundary        TEXT NOT NULL          -- multipolygon6
);

CREATE TABLE district (
  id              TEXT PRIMARY KEY,      -- 'osm:r<relation id>', 'osm:w<way id>' or 'curated:<slug>'
  kind            TEXT NOT NULL CHECK (kind IN ('district', 'quarter', 'neighbourhood')),
  osm_relation_id INTEGER,               -- NULL for curated and way-drawn areas
  name_ka         TEXT NOT NULL,
  name_en         TEXT,
  center_lat      REAL NOT NULL,         -- pole of inaccessibility, for labels/camera
  center_lon      REAL NOT NULL,
  min_lat         REAL NOT NULL,
  min_lon         REAL NOT NULL,
  max_lat         REAL NOT NULL,
  max_lon         REAL NOT NULL,
  area_m2         REAL NOT NULL,
  boundary        TEXT NOT NULL          -- multipolygon6
);

CREATE TABLE street (
  id          TEXT PRIMARY KEY,          -- stable UUID from data/cities/<city>/identity.json
  name_ka     TEXT NOT NULL,
  name_en     TEXT,
  road_class  TEXT NOT NULL,             -- highest OSM highway class by length
  difficulty  TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'expert')),
  length_m    REAL NOT NULL,
  mid_lat     REAL NOT NULL,             -- point at half the length of the longest part
  mid_lon     REAL NOT NULL,
  min_lat     REAL NOT NULL,
  min_lon     REAL NOT NULL,
  max_lat     REAL NOT NULL,
  max_lon     REAL NOT NULL,
  geometry    TEXT NOT NULL              -- multiline6
);
CREATE INDEX street_difficulty ON street (difficulty);

CREATE TABLE street_district (
  street_id   TEXT NOT NULL REFERENCES street (id),
  district_id TEXT NOT NULL REFERENCES district (id),
  length_m    REAL NOT NULL,             -- street length inside the district
  share       REAL NOT NULL,             -- length_m / street.length_m
  PRIMARY KEY (street_id, district_id)
) WITHOUT ROWID;
CREATE INDEX street_district_district ON street_district (district_id);
```

### Rules baked in by the pipeline

- Streets: OSM `highway` in motorway, trunk, primary, secondary, tertiary, unclassified,
  residential, living_street; named; not `access=private`. Ways sharing a normalised name are merged
  when they lie within 30 m of each other (DBSCAN in UTM), so same-name streets far apart stay
  separate.
- Difficulty: easy = motorway/trunk/primary, medium = secondary, hard = tertiary,
  expert = unclassified/residential/living_street.
- `street_district`: a street belongs to a district when its length inside is ≥ 150 m or its share
  is ≥ 0.3. A street can belong to several districts.
- Districts are the `subarea` members of the city relation (any `admin_level`). Quarters and
  neighbourhoods are OSM `place=quarter` and `place=neighbourhood` areas (closed ways or
  multipolygons) clipped to the city, their kind taken from the tag, plus curated neighbourhoods
  from `data/cities/<city>/curation/neighbourhoods.geojson`. When OSM areas share a name only the
  smallest is kept, and an area with fewer than 10 streets is dropped (too small for a round).
  Quarters tile most of a city; neighbourhoods are smaller and may overlap quarters, each other and
  districts.

### Fixture scope

`pipeline build <city> --fixture` writes a pack with `meta.scope = 'fixture'` containing the full
`city` row, the fixture district (Vake, `osm:r11300449` for Tbilisi), the quarters and
neighbourhoods whose centre lies in it, and only the streets assigned to the district (the smaller
areas link only those). The app bundles it as `apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite`
(not gzipped).

## Licence

Packs are a Derivative Database of OpenStreetMap, © OpenStreetMap contributors, available under the
ODbL 1.0 (see `data/LICENSE-ODbL.md`). Every map in the app shows the attribution.
