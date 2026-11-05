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

CREATE UNIQUE INDEX ON pipeline.district (id);
CREATE INDEX ON pipeline.district USING gist (geom);
