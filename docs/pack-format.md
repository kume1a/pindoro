# City pack format (v5)

A city pack is a read-only SQLite database built by `pipeline` from OpenStreetMap data and
downloaded by the app. Packs are immutable: a new build gets a new `version` and a new file name.

v5 (2026-11) adds the v3 route items: the road graph becomes directed (`road_edge.oneway`), takes
unnamed ways and `*_link` roads as connector edges (`street_id` NULL) and gains `turn_restriction`;
junctions carry their OSM node id (`junction.node_id`, the stable part of route item ids); and the
pack adds `bridge`, `landmark` and `junction_item`. The app installs v3 to v5; route items need v5.

v4 (2026-11) adds the v3 learning system's curriculum data: each street's `tier`, `ring`, `bank`,
`chunk_id` and `etymology`, each smaller area's raion (`district.parent_id`), and the `family` and
`chunk_neighbour` tables. The city centre is now `centre` from `city.yaml`. The app installs v3 and
v4; learning needs v4, and a v3 pack keeps working for Explore until the background refresh
replaces it.

v3 (2026-11) adds the road graph (`junction`, `road_edge`) for road trips. The app installs v3 and
still opens a v2 pack already on the phone, without road trips, until the background refresh
replaces it.

v2 (2026-11) adds the `quarter` area kind (OSM `place=quarter`, which v1 stored as
`neighbourhood`) and puts area centres at the pole of inaccessibility. The app downloads only the
format it supports; v1 packs already on a phone still open.

## Files

```
<PACKS_DIR>/
  tbilisi/
    manifest.json                               # current pack of the city
    tbilisi-20261105T221700Z.sqlite.gz          # gzipped pack, immutable, cached forever
```

`version` is the UTC build time formatted `YYYYMMDDTHHMMSSZ`, so versions sort lexically.

### manifest.json

```json
{
  "format_version": 5,
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

The API's `/v1/catalog` lists every city's manifest with absolute pack URLs; the app reads only
that.

## Encodings

- **polyline6** – Google polyline algorithm with 1e6 precision, `(lat, lon)` order, rounding half
  away from zero (`@pindoro/geo` and `pindoro_core` share golden vectors).
- **multiline6** – JSON array of polyline6 strings, one per line part: `["_izlhA~rl…", "…"]`.
- **multipolygon6** – JSON array of polygons; each polygon is an array of closed rings (first outer,
  then holes), each ring a polyline6 string: `[["outer", "hole"], ["outer"]]`.

All coordinates are WGS84. Lengths and areas are metres / square metres measured in the city's UTM
zone. Street geometry is simplified to 3 m.

## Schema

`PRAGMA user_version = 5` equals `format_version`.

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
  center_lat      REAL NOT NULL,         -- `centre` in city.yaml (Freedom Square for Tbilisi)
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
  boundary        TEXT NOT NULL,         -- multipolygon6
  parent_id       TEXT REFERENCES district (id) -- a smaller area's raion; NULL for a raion
);

CREATE TABLE street (
  id          TEXT PRIMARY KEY,          -- stable UUID from the city's live identity.json
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
  geometry    TEXT NOT NULL,             -- multiline6
  tier        TEXT NOT NULL CHECK (tier IN ('A', 'B', 'C')),
  ring        INTEGER NOT NULL,          -- floor(centroid's distance from the city centre / 2 km)
  bank        TEXT NOT NULL CHECK (bank IN ('L', 'R')), -- side of the river, facing downstream
  chunk_id    TEXT REFERENCES district (id), -- the neighbourhood that teaches it
  etymology   TEXT                       -- OSM name:etymology
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

CREATE TABLE junction (
  id      INTEGER PRIMARY KEY,           -- pack-local; not stable across pack versions
  node_id INTEGER NOT NULL,              -- OSM node id: stable, `n<node_id>` in route item ids
  lat     REAL NOT NULL,
  lon     REAL NOT NULL
);

CREATE TABLE bridge (
  id       TEXT PRIMARY KEY,             -- 'w<lowest OSM way id of the bridge>'
  name_ka  TEXT NOT NULL,                -- bridge:name, else the name of the street it carries
  name_en  TEXT,
  mid_lat  REAL NOT NULL,
  mid_lon  REAL NOT NULL,
  geometry TEXT NOT NULL                 -- multiline6
);

CREATE TABLE road_edge (
  id            INTEGER PRIMARY KEY,
  from_junction INTEGER NOT NULL REFERENCES junction (id),
  to_junction   INTEGER NOT NULL REFERENCES junction (id),
  street_id     TEXT REFERENCES street (id), -- NULL: a connector (an unnamed way or a *_link)
  oneway        INTEGER NOT NULL CHECK (oneway IN (-1, 0, 1)), -- 1 from→to only, -1 to→from only
  bridge_id     TEXT REFERENCES bridge (id),
  length_m      REAL NOT NULL,           -- along the unsimplified way
  geometry      TEXT NOT NULL            -- polyline6 from from_junction to to_junction
);

CREATE TABLE turn_restriction (
  from_edge    INTEGER NOT NULL REFERENCES road_edge (id),
  via_junction INTEGER NOT NULL REFERENCES junction (id),
  to_edge      INTEGER NOT NULL REFERENCES road_edge (id),
  only         INTEGER NOT NULL CHECK (only IN (0, 1)), -- 0 no_*: forbidden; 1 only_*: the only exit
  PRIMARY KEY (from_edge, via_junction, to_edge)
) WITHOUT ROWID;

CREATE TABLE landmark (
  id       TEXT PRIMARY KEY,             -- 'osm:n<id>', 'osm:w<id>', 'osm:r<id>'
  kind     TEXT NOT NULL,                -- metro, bridge, square, roundabout, fuel, worship, mall, …
  name_ka  TEXT NOT NULL,                -- the name, else the brand
  name_en  TEXT,
  brand    TEXT,
  salience REAL NOT NULL,                -- SPEC §9 without the turn-dependent structural part
  lat      REAL NOT NULL,
  lon      REAL NOT NULL
);

CREATE TABLE junction_item (
  junction_id   INTEGER NOT NULL REFERENCES junction (id),
  approach_edge INTEGER NOT NULL REFERENCES road_edge (id),
  exit_edge     INTEGER NOT NULL REFERENCES road_edge (id),
  layer         TEXT NOT NULL CHECK (layer IN ('skeleton', 'district', 'gateway_out', 'gateway_in', 'bridge')),
  rank          INTEGER NOT NULL,        -- coverage order, 1 first
  chunk_id      TEXT REFERENCES district (id), -- a gateway's neighbourhood
  dest_chunk_id TEXT REFERENCES district (id), -- where the routes through it mostly head
  landmark_id   TEXT REFERENCES landmark (id), -- the most salient within 60 m for this turn
  landmark_side TEXT CHECK (landmark_side IN ('left', 'right')), -- seen driving in on the approach
  bridge_id     TEXT REFERENCES bridge (id), -- the bridge the exit leads onto (layer `bridge`)
  PRIMARY KEY (junction_id, approach_edge, exit_edge)
) WITHOUT ROWID;

CREATE TABLE family (
  parent_street_id TEXT NOT NULL REFERENCES street (id),
  child_street_id  TEXT PRIMARY KEY REFERENCES street (id),
  kind             TEXT NOT NULL CHECK (kind IN ('lane', 'dead_end', 'passage')),
  n                INTEGER NOT NULL,     -- the Roman numeral
  orphan           INTEGER NOT NULL CHECK (orphan IN (0, 1)) -- child centroid > 1.5 km away
) WITHOUT ROWID;
CREATE INDEX family_parent ON family (parent_street_id);

CREATE TABLE chunk_neighbour (
  chunk_a TEXT NOT NULL REFERENCES district (id),
  chunk_b TEXT NOT NULL REFERENCES district (id),
  PRIMARY KEY (chunk_a, chunk_b)         -- both orders are stored
) WITHOUT ROWID;
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
- Road graph: the ways of the pack's streets plus connector ways (drivable classes without a name,
  and every `*_link`). A junction is an OSM node two of them share (or one way meets twice), or a
  way's end; an edge is a way's stretch between two consecutive junctions, simplified to 3 m with
  both ends kept. `oneway`: `oneway=yes|1|true` and roundabouts 1, `oneway=-1|reverse` -1,
  motorways 1 unless `oneway=no`; `oneway:psv` is ignored. Ways whose geometry lost points against
  their node list are left out. `validate` requires 90 % of the edges in the largest connected
  part.
- Turn restrictions: OSM `type=restriction` relations with one `from` way, a `via` node and one
  `to` way (way-via restrictions are left out), `restriction:motorcar` before `restriction`, none
  that `except` cars; one row per pair of edges of those ways meeting at the via junction.
- Bridges: named `bridge=*` ways (not `no`) crossing the city's `river`, with the same-name bridge
  ways within 200 m of them, grouped by name (`bridge:name`, else the name of the street carried).
- Landmarks (SPEC §9): named or branded OSM points of interest of the §9 kinds, named roundabouts
  and named bridges; `salience` = 0.30 type + 0.15 brand or name + 0.15 size + 0.10 wiki + 0.15
  uniqueness (one over the same kind within 300 m).
- Junction items (`src/routes.ts`, SPEC §6.6): 20 000 origin–destination pairs drawn by street
  length (seeded), each driven by the shortest legal route; every turn with another legal way on
  is a decision `(junction, approach, exit)`. The most driven decisions are taken until they cover
  90 % of the decisions driven; `rank` is that order. Layer: `bridge` when the exit leads onto a
  bridge (its own edge, or one reached before the next junction with a choice), `gateway_out` when it leaves a tier C street for a tier A or B one (its `chunk_id` the tier
  C street's), `gateway_in` the other way, `skeleton` between tier A streets, else `district`.
  Each item gets the landmark within 60 m with the highest salience plus structural (1.0 within
  40 m before the turn, 0.6 within 40 m after it, else 0.3), and its side. The build writes the
  coverage report to `out/<city>/coverage.md`.

- Curriculum (`sql/80_learning.sql`):
  - Tier: `A` the skeleton (motorway, trunk, primary), `B` the grid (secondary, tertiary), `C` the
    rest.
  - Ring and bank use the street's centroid. The river is `river` in `city.yaml`, a downstream
    line; `L` is the left bank facing downstream.
  - Chunk: the `neighbourhood` holding most of the street's length; a street in none goes to the
    nearest neighbourhood. Chunks border each other when their boundaries come within 50 m.
  - A smaller area's raion is the district holding its centre (the nearest one at the city's
    edge).
  - Families come from `name_ka`: `<prefix> <Roman numeral> <შესახვევი | ჩიხი | გასასვლელი>` (kinds
    `lane`, `dead_end`, `passage`) belongs to the nearest street the prefix names: its name minus
    the type word (`ავთო ვარაზის ქუჩა`), or with its last word in the genitive (`… გზატკეცილი`,
    `… ქუჩა`, and `… I შესახვევი` for a lane's own dead ends). Names without a numeral are not
    families. `docs/research/family-check.md` has the data check.

### Fixture scope

`pipeline build <city> --fixture` writes a pack with `meta.scope = 'fixture'` containing the full
`city` row, the fixture district (Vake, `osm:r11300449` for Tbilisi), the streets assigned to the
district whose id matched a live one (a street that would get a new id stays out, so the fixture
never holds an id the server's packs don't know), with their road edges, the connectors between
their junctions and the junctions those use, the restrictions, bridges and junction items on those
edges and the items' landmarks, and the quarters and neighbourhoods whose centre lies in the district and that still link at
least `MIN_AREA_STREETS` (10) of those streets (they link only those). A street whose chunk, or an
area whose raion, is outside the fixture gets NULL; families and chunk neighbours need both ends in
it. The app bundles it as
`apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite` (not gzipped).

## Licence

Packs are a Derivative Database of OpenStreetMap, © OpenStreetMap contributors, available under the
ODbL 1.0 (see `data/LICENSE-ODbL.md`). Every map in the app shows the attribution.
