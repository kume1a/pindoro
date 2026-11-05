-- A street belongs to a district when >= 150 m of it lies inside, or >= 30 % of its length.

CREATE TABLE pipeline.street_district AS
SELECT s.key AS street_key,
       d.id AS district_id,
       x.length_m,
       x.length_m / s.length_m AS share
FROM pipeline.street s
JOIN pipeline.district d ON ST_Intersects(s.geom, d.geom)
CROSS JOIN LATERAL (SELECT ST_Length(ST_Intersection(s.geom, d.geom)) AS length_m) x
WHERE s.length_m > 0
  AND (x.length_m >= 150 OR x.length_m / s.length_m >= 0.3);

CREATE INDEX ON pipeline.street_district (district_id);
