-- Route data (pack format 5): the bridges over the river, each junction's bank, and the landmark
-- candidates with the part of their salience that doesn't depend on a turn (SPEC §9). Junction
-- items and their landmarks are chosen afterwards by `src/routes.ts`.

-- Bridges (SPEC §16.29): named bridge ways crossing `river`, grouped by their bridge's name (else
-- the street they carry), with the same-name bridge ways within 200 m of them (a bridge split into
-- several ways). Unnamed bridges are left out: a bridge question names them. The id is the
-- lowest way id.
CREATE TABLE pipeline.bridge AS
WITH river AS (
  SELECT ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(p.river), 4326), p.utm_srid) AS geom
  FROM pipeline.params p
),
way AS (
  SELECT g.way_id, g.geom,
         coalesce(nullif(btrim(o.bridge_name), ''), nullif(btrim(o.name_ka), ''), nullif(btrim(o.name), ''))
           AS name_ka,
         nullif(btrim(o.name_en), '') AS name_en
  FROM pipeline.graph_way g
  JOIN osm.roads o USING (way_id)
  WHERE g.bridge_way IS NOT NULL
),
crossing AS (
  SELECT w.* FROM way w, river WHERE w.name_ka IS NOT NULL AND ST_Intersects(w.geom, river.geom)
),
member AS (
  SELECT DISTINCT w.*
  FROM way w
  JOIN crossing c ON pipeline.normalise_name(c.name_ka) = pipeline.normalise_name(w.name_ka)
                 AND ST_DWithin(c.geom, w.geom, 200)
)
SELECT 'w' || min(way_id) AS id,
       min(name_ka) AS name_ka,
       min(name_en) AS name_en,
       array_agg(way_id ORDER BY way_id) AS way_ids,
       ST_Transform(ST_Multi(ST_Union(geom)), 4326) AS geom
FROM member
GROUP BY pipeline.normalise_name(name_ka);

CREATE TABLE pipeline.edge_bridge AS
SELECT e.id AS edge_id, b.id AS bridge_id
FROM pipeline.road_edge e
JOIN pipeline.bridge b ON e.way_id = ANY (b.way_ids);

-- Each junction's side of the river, as for streets (sql/80_learning.sql).
CREATE TABLE pipeline.junction_bank AS
WITH river AS (
  SELECT ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(p.river), 4326), p.utm_srid) AS geom, p.utm_srid
  FROM pipeline.params p
),
j AS (
  SELECT jp.id, ST_Transform(jp.geom, river.utm_srid) AS c, river.geom AS river,
         ST_LineLocatePoint(river.geom, ST_Transform(jp.geom, river.utm_srid)) AS f
  FROM pipeline.junction_point jp, river
)
SELECT j.id,
       CASE
         WHEN (ST_X(flow.b) - ST_X(flow.a)) * (ST_Y(j.c) - ST_Y(flow.a))
            - (ST_Y(flow.b) - ST_Y(flow.a)) * (ST_X(j.c) - ST_X(flow.a)) > 0 THEN 'L'
         ELSE 'R'
       END AS bank
FROM j
CROSS JOIN LATERAL (
  SELECT ST_LineInterpolatePoint(j.river, greatest(j.f - 1e-4, 0)) AS a,
         ST_LineInterpolatePoint(j.river, least(j.f + 1e-4, 1)) AS b
) flow;

-- Landmark candidates (SPEC §9) with a name or brand: OSM points of interest, named roundabouts and
-- the bridges. `base` is the salience without its turn-dependent `structural` part:
-- 0.30 type + 0.15 brand or name + 0.15 size + 0.10 wiki + 0.15 uniqueness.
CREATE TABLE pipeline.landmark AS
WITH params AS (SELECT utm_srid FROM pipeline.params),
raw AS (
  SELECT 'osm:' || lower(p.osm_type) || p.osm_id AS id, p.kind,
         coalesce(nullif(btrim(p.name_ka), ''), nullif(btrim(p.name), '')) AS name_ka,
         nullif(btrim(p.name_en), '') AS name_en,
         nullif(btrim(p.brand), '') AS brand,
         coalesce(p.wiki, false) AS wiki,
         ST_Transform(p.geom, params.utm_srid) AS geom,
         CASE WHEN p.levels ~ '^[0-9]+(\.[0-9]+)?$' THEN p.levels::float8 END AS levels
  FROM osm.pois p, params
  UNION ALL
  SELECT 'osm:w' || r.way_id, 'roundabout', coalesce(nullif(btrim(r.name_ka), ''), btrim(r.name)),
         nullif(btrim(r.name_en), ''), NULL, false, ST_Transform(r.geom, params.utm_srid), NULL
  FROM osm.roads r, params
  WHERE r.junction = 'roundabout' AND coalesce(nullif(btrim(r.name_ka), ''), nullif(btrim(r.name), '')) IS NOT NULL
  UNION ALL
  SELECT 'osm:' || b.id, 'bridge', b.name_ka, b.name_en, NULL, false, ST_Transform(b.geom, params.utm_srid), NULL
  FROM pipeline.bridge b, params
),
placed AS (
  SELECT r.*, ST_PointOnSurface(r.geom) AS at,
         CASE WHEN ST_Dimension(r.geom) = 2 THEN ST_Area(r.geom)
              WHEN r.levels IS NOT NULL THEN r.levels * 100 END AS footprint
  FROM raw r
  WHERE (r.name_ka IS NOT NULL OR r.brand IS NOT NULL)
)
SELECT p.id, p.kind, coalesce(p.name_ka, p.brand) AS name_ka, p.name_en, p.brand,
       ST_Transform(p.at, 4326) AS geom,
       0.30 * CASE p.kind
                WHEN 'metro' THEN 1.0 WHEN 'bridge' THEN 1.0
                WHEN 'square' THEN 0.9 WHEN 'roundabout' THEN 0.9 WHEN 'fuel' THEN 0.9
                WHEN 'worship' THEN 0.8 WHEN 'mall' THEN 0.8 WHEN 'supermarket' THEN 0.8 WHEN 'station' THEN 0.8
                WHEN 'hospital' THEN 0.7 WHEN 'university' THEN 0.7 WHEN 'monument' THEN 0.7
                WHEN 'attraction' THEN 0.7 WHEN 'tower' THEN 0.7
                WHEN 'stadium' THEN 0.6 WHEN 'park' THEN 0.6
                ELSE 0.4
              END
       + 0.15 * CASE WHEN p.brand IS NOT NULL OR p.name_ka IS NOT NULL THEN 1 ELSE 0 END
       + 0.15 * CASE WHEN p.footprint > 1 THEN least(1, log(p.footprint) / 4) ELSE 0 END
       + 0.10 * CASE WHEN p.wiki THEN 1 ELSE 0 END
       + 0.15 / (SELECT count(*) FROM placed o WHERE o.kind = p.kind AND ST_DWithin(o.at, p.at, 300))
         AS base
FROM placed p;

CREATE INDEX ON pipeline.landmark USING gist (geom);

-- The junction items (SPEC §2.1, §6.6), filled by `src/routes.ts` once the SQL steps have run.
CREATE TABLE pipeline.junction_item (
  junction_id   bigint NOT NULL,
  approach_edge bigint NOT NULL,
  exit_edge     bigint NOT NULL,
  layer         text NOT NULL,
  rank          int NOT NULL,
  chunk_id      text,
  dest_chunk_id text,
  landmark_id   text,
  landmark_side text,
  bridge_id     text,
  PRIMARY KEY (junction_id, approach_edge, exit_edge)
);
