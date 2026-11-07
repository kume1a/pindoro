-- Curated neighbourhoods (data/cities/<city>/curation/neighbourhoods.geojson), staged raw by the CLI.

INSERT INTO pipeline.district (id, kind, osm_relation_id, name_ka, name_en, geom)
SELECT 'curated:' || n.slug,
       'neighbourhood',
       NULL,
       n.name_ka,
       n.name_en,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(
         ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(n.geojson), 4326), p.utm_srid)), 3))
FROM pipeline.neighbourhood_raw n, pipeline.params p;

-- OpenStreetMap quarters and neighbourhoods (place=quarter|neighbourhood areas), clipped to the city.
-- When several share a name, only the smallest is kept.

INSERT INTO pipeline.district (id, kind, osm_relation_id, name_ka, name_en, geom)
SELECT ranked.id, 'neighbourhood', ranked.osm_relation_id, ranked.name_ka, ranked.name_en, ranked.geom
FROM (
  SELECT x.*, row_number() OVER (PARTITION BY x.name_ka ORDER BY ST_Area(x.geom), x.id) AS nth
  FROM (
    SELECT 'osm:' || lower(a.osm_type) || a.osm_id AS id,
           CASE WHEN a.osm_type = 'R' THEN a.osm_id END AS osm_relation_id,
           btrim(coalesce(nullif(btrim(a.name_ka), ''), a.name)) AS name_ka,
           nullif(btrim(a.name_en), '') AS name_en,
           ST_Multi(ST_CollectionExtract(ST_Intersection(
             ST_MakeValid(ST_Transform(a.geom, p.utm_srid)), c.geom), 3)) AS geom
    FROM osm.place_areas a, pipeline.params p, pipeline.city c
    WHERE coalesce(nullif(btrim(a.name_ka), ''), nullif(btrim(a.name), '')) IS NOT NULL
      AND ST_Intersects(ST_Transform(a.geom, p.utm_srid), c.geom)
  ) x
  WHERE NOT ST_IsEmpty(x.geom)
) ranked
WHERE ranked.nth = 1
  AND NOT EXISTS (SELECT 1 FROM pipeline.district d WHERE d.id = ranked.id);

CREATE UNIQUE INDEX ON pipeline.district (id);
CREATE INDEX ON pipeline.district USING gist (geom);
