-- Every named place in the city (SPEC §16.23 item 132): a destination to drive to, found by its
-- name or brand, with its address, opening hours and contacts as OSM has them. It stands at a
-- point on its surface; an area keeps its `outline` for the map to light up.
CREATE TABLE pipeline.poi AS
WITH params AS (SELECT utm_srid FROM pipeline.params),
raw AS (
  SELECT 'osm:' || lower(p.osm_type) || p.osm_id AS id, p.key, p.kind,
         coalesce(nullif(btrim(p.name_ka), ''), nullif(btrim(p.name), ''),
                  nullif(btrim(p.brand), '')) AS name_ka,
         nullif(btrim(p.name_en), '') AS name_en,
         nullif(btrim(p.brand), '') AS brand,
         nullif(btrim(p.addr_street), '') AS street,
         nullif(btrim(p.addr_housenumber), '') AS housenumber,
         nullif(btrim(p.opening_hours), '') AS hours,
         nullif(btrim(p.phone), '') AS phone,
         nullif(btrim(p.website), '') AS website,
         ST_Transform(p.geom, params.utm_srid) AS geom
  FROM osm.named_pois p, params
)
SELECT r.id, r.key, r.kind, r.name_ka, r.name_en, r.brand, r.street, r.housenumber, r.hours,
       r.phone, r.website, ST_Transform(s.at, 4326) AS geom,
       CASE WHEN ST_Dimension(r.geom) = 2
            THEN ST_Multi(ST_Transform(ST_SimplifyPreserveTopology(r.geom, 3), 4326)) END AS outline
FROM raw r
CROSS JOIN LATERAL (SELECT ST_PointOnSurface(r.geom) AS at) s
WHERE r.name_ka IS NOT NULL
  AND EXISTS (SELECT 1 FROM pipeline.city c WHERE ST_Intersects(c.geom, s.at));

CREATE INDEX ON pipeline.poi USING gist (geom);
