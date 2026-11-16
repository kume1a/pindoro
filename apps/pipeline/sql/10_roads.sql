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

-- Connector ways (SPEC §16.28): drivable ways that are no street, an unnamed one or a `*_link`.
-- They join the road graph so routes don't detour round a missing ramp, but are never asked.
CREATE TABLE pipeline.connector AS
SELECT way_id, ST_Transform(geom, (SELECT utm_srid FROM pipeline.params)) AS geom
FROM osm.roads
WHERE coalesce(access, '') <> 'private'
  AND way_id NOT IN (SELECT way_id FROM pipeline.road)
  AND (highway LIKE '%\_link'
       OR (pipeline.class_rank(highway) IS NOT NULL AND pipeline.normalise_name(coalesce(name_ka, name)) IS NULL));
