-- Merge ways into streets: same normalised name AND within 30 m of each other (DBSCAN eps, metres in UTM).
-- Same-name clusters far apart stay separate streets.

CREATE TABLE pipeline.road_cluster AS
SELECT r.*,
       ST_ClusterDBSCAN(r.geom, eps := 30, minpoints := 1) OVER (PARTITION BY r.norm_name) AS cluster
FROM pipeline.road r;

CREATE TABLE pipeline.street AS
WITH merged AS (
  SELECT norm_name,
         cluster,
         array_agg(way_id ORDER BY way_id) AS way_ids,
         ST_Multi(ST_LineMerge(ST_Union(geom))) AS geom
  FROM pipeline.road_cluster
  GROUP BY norm_name, cluster
),
road_class AS (
  -- class covering the most length; ties go to the higher class
  SELECT DISTINCT ON (norm_name, cluster) norm_name, cluster, highway
  FROM pipeline.road_cluster
  GROUP BY norm_name, cluster, highway
  ORDER BY norm_name, cluster, sum(ST_Length(geom)) DESC, pipeline.class_rank(highway)
),
name_ka AS (
  -- spelling used on the longest stretch
  SELECT DISTINCT ON (norm_name, cluster) norm_name, cluster, name_ka
  FROM pipeline.road_cluster
  GROUP BY norm_name, cluster, name_ka
  ORDER BY norm_name, cluster, sum(ST_Length(geom)) DESC, name_ka
),
name_en AS (
  SELECT DISTINCT ON (norm_name, cluster) norm_name, cluster, name_en
  FROM pipeline.road_cluster
  WHERE name_en IS NOT NULL
  GROUP BY norm_name, cluster, name_en
  ORDER BY norm_name, cluster, sum(ST_Length(geom)) DESC, name_en
)
SELECT row_number() OVER (ORDER BY m.norm_name, m.way_ids) AS key,
       m.norm_name,
       ka.name_ka,
       en.name_en,
       c.highway AS road_class,
       CASE
         WHEN c.highway IN ('motorway', 'trunk', 'primary') THEN 'easy'
         WHEN c.highway = 'secondary' THEN 'medium'
         WHEN c.highway = 'tertiary' THEN 'hard'
         ELSE 'expert'
       END AS difficulty,
       m.way_ids,
       ST_Length(m.geom) AS length_m,
       m.geom
FROM merged m
JOIN road_class c USING (norm_name, cluster)
JOIN name_ka ka USING (norm_name, cluster)
LEFT JOIN name_en en USING (norm_name, cluster);

CREATE UNIQUE INDEX ON pipeline.street (key);
CREATE INDEX ON pipeline.street USING gist (geom);
