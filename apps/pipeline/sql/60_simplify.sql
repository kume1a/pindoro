-- Pack-ready WGS84 geometry: simplified to 3 m in UTM. The midpoint is taken on the simplified line so it
-- always lies on the geometry the app draws.

CREATE TABLE pipeline.pack_street AS
SELECT s.key,
       ST_Transform(simple.geom, 4326) AS geom,
       ST_Transform(ST_LineInterpolatePoint(longest.geom, 0.5), 4326) AS mid
FROM pipeline.street s
CROSS JOIN LATERAL (SELECT ST_Multi(ST_SimplifyPreserveTopology(s.geom, 3)) AS geom) simple
CROSS JOIN LATERAL (
  SELECT part.geom FROM ST_Dump(simple.geom) part ORDER BY ST_Length(part.geom) DESC LIMIT 1
) longest;

CREATE TABLE pipeline.pack_area AS
SELECT d.id,
       ST_Area(d.geom) AS area_m2,
       ST_Transform(ST_PointOnSurface(d.geom), 4326) AS center,
       ST_Transform(ST_Multi(ST_SimplifyPreserveTopology(d.geom, 3)), 4326) AS geom
FROM pipeline.district d
UNION ALL
SELECT 'city',
       ST_Area(c.geom),
       ST_Transform(ST_PointOnSurface(c.geom), 4326),
       ST_Transform(ST_Multi(ST_SimplifyPreserveTopology(c.geom, 3)), 4326)
FROM pipeline.city c;
