-- Playable roads: named, drivable, not private; names normalised for grouping. Geometry in the city's UTM.

CREATE FUNCTION pipeline.normalise_name(raw text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(btrim(regexp_replace(lower(translate(raw, '«»„“”"''`', '')), '\s+', ' ', 'g')), '')
$$;

CREATE FUNCTION pipeline.class_rank(highway text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT array_position(
    ARRAY['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street'],
    highway)
$$;

CREATE TABLE pipeline.road AS
SELECT r.way_id, r.highway, r.name_ka, r.name_en, r.etymology, pipeline.normalise_name(r.name_ka) AS norm_name,
       r.geom
FROM (
  SELECT way_id,
         highway,
         access,
         coalesce(nullif(btrim(name_ka), ''), btrim(name)) AS name_ka,
         nullif(btrim(name_en), '') AS name_en,
         nullif(btrim(etymology), '') AS etymology,
         ST_Transform(geom, (SELECT utm_srid FROM pipeline.params)) AS geom
  FROM osm.roads
) r
-- the allow-list drops *_link, service, footway, path, cycleway, steps, track, ...
WHERE pipeline.class_rank(r.highway) IS NOT NULL
  AND coalesce(r.access, '') <> 'private'
  AND pipeline.normalise_name(r.name_ka) IS NOT NULL;

CREATE INDEX ON pipeline.road (norm_name);

-- How a way may be driven (SPEC §2.1): 1 along its nodes only, -1 against them, 0 both ways.
-- `oneway=yes|1|true` and roundabouts are one-way along, `oneway=-1|reverse` against; motorways
-- are one-way unless tagged otherwise; `oneway:psv` is ignored.
CREATE FUNCTION pipeline.oneway(oneway text, junction text, highway text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN oneway IN ('yes', '1', 'true') THEN 1
    WHEN oneway IN ('-1', 'reverse') THEN -1
    WHEN oneway IN ('no', 'false', '0') THEN 0
    WHEN junction IN ('roundabout', 'circular') OR highway IN ('motorway', 'motorway_link') THEN 1
    ELSE 0
  END
$$;

-- A way's lane arrows driving along its nodes (`dir` 1) or against them (-1), left to right in
-- that driving direction, as OSM has them (`left|through;right`): the `:forward` / `:backward`
-- tag, else the plain `turn:lanes` when the way is one-way in `dir` (`oneway` from
-- pipeline.oneway); a two-way way's plain tag says no direction and is ignored. NULL: unmapped.
CREATE FUNCTION pipeline.turn_lanes(dir int, oneway int, plain text, directional text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(nullif(btrim(directional), ''),
                  CASE WHEN oneway = dir THEN nullif(btrim(plain), '') END)
$$;

-- A `maxspeed` tag in km/h: a number (km/h unless `mph`), or a Georgian zone (`GE:urban` 60,
-- `GE:rural` 90, `GE:motorway` 110, `GE:living_street` 20); NULL for anything else (`none`,
-- `signals`, a typo).
CREATE FUNCTION pipeline.maxspeed_kmh(maxspeed text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN m[1] IS NOT NULL THEN round(m[1]::numeric * CASE WHEN m[2] IS NULL THEN 1 ELSE 1.609344 END)::int
    WHEN maxspeed = 'GE:urban' THEN 60
    WHEN maxspeed = 'GE:rural' THEN 90
    WHEN maxspeed = 'GE:motorway' THEN 110
    WHEN maxspeed = 'GE:living_street' THEN 20
  END
  FROM (SELECT regexp_match(maxspeed, '^\s*(\d{1,3})\s*(mph)?\s*$') AS m) t
$$;

-- A compass `direction` in degrees from north: a number, or N, NNE … NNW; NULL for anything else
-- (`forward`, `both`).
CREATE FUNCTION pipeline.direction_deg(direction text) RETURNS real
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN direction ~ '^\s*\d+(\.\d+)?\s*$' THEN direction::real
    ELSE (array_position(ARRAY['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'],
                         upper(trim(direction))) - 1) * 22.5
  END
$$;

-- Connector ways (SPEC §16.28): drivable ways that are no street, an unnamed one or a `*_link`.
-- They join the road graph so routes don't detour round a missing ramp, but are never asked.
CREATE TABLE pipeline.connector AS
SELECT way_id, ST_Transform(geom, (SELECT utm_srid FROM pipeline.params)) AS geom
FROM osm.roads
WHERE coalesce(access, '') <> 'private'
  AND way_id NOT IN (SELECT way_id FROM pipeline.road)
  AND (highway LIKE '%\_link'
       OR (pipeline.class_rank(highway) IS NOT NULL AND pipeline.normalise_name(coalesce(name_ka, name)) IS NULL));
