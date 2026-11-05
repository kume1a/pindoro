-- City outline and districts. Districts are the `subarea` members of the city relation, whatever their
-- admin_level (Tbilisi raions carry 6, 7 and 10).

CREATE TABLE pipeline.city AS
SELECT b.relation_id, ST_Multi(ST_Transform(b.geom, p.utm_srid)) AS geom
FROM osm.boundaries b, pipeline.params p
WHERE b.relation_id = p.city_relation_id AND b.geom IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pipeline.city) THEN
    RAISE EXCEPTION 'city relation % not found (or has no valid geometry)',
      (SELECT city_relation_id FROM pipeline.params);
  END IF;
END $$;

CREATE TABLE pipeline.district AS
SELECT 'osm:r' || b.relation_id AS id,
       'district'::text AS kind,
       b.relation_id AS osm_relation_id,
       btrim(coalesce(nullif(btrim(b.name_ka), ''), b.name)) AS name_ka,
       nullif(btrim(b.name_en), '') AS name_en,
       ST_Multi(ST_Transform(b.geom, p.utm_srid)) AS geom
FROM pipeline.params p
JOIN osm.subareas s ON s.parent_id = p.city_relation_id AND s.role = 'subarea'
JOIN osm.boundaries b ON b.relation_id = s.child_id
WHERE b.geom IS NOT NULL;

DO $$
DECLARE
  missing bigint[];
BEGIN
  SELECT array_agg(e ORDER BY e) INTO missing
  FROM pipeline.params p, unnest(p.expect_relations) e
  WHERE NOT EXISTS (SELECT 1 FROM pipeline.district d WHERE d.osm_relation_id = e);
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'expected district relations missing: %', missing;
  END IF;
END $$;
