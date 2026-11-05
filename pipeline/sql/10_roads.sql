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
SELECT r.way_id, r.highway, r.name_ka, r.name_en, pipeline.normalise_name(r.name_ka) AS norm_name, r.geom
FROM (
  SELECT way_id,
         highway,
         access,
         coalesce(nullif(btrim(name_ka), ''), btrim(name)) AS name_ka,
         nullif(btrim(name_en), '') AS name_en,
         ST_Transform(geom, (SELECT utm_srid FROM pipeline.params)) AS geom
  FROM osm.roads
) r
-- the allow-list drops *_link, service, footway, path, cycleway, steps, track, ...
WHERE pipeline.class_rank(r.highway) IS NOT NULL
  AND coalesce(r.access, '') <> 'private'
  AND pipeline.normalise_name(r.name_ka) IS NOT NULL;

CREATE INDEX ON pipeline.road (norm_name);
