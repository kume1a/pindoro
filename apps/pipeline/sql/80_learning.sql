-- Curriculum data (pack format 4): each street's tier, ring, river bank, chunk and (format 10)
-- outskirts, each area's raion, the chunks that border each other, and the lane families parsed
-- from the Georgian names.

-- The outskirts must still name a neighbourhood and a street each: a renamed one fails the build
-- rather than teach its streets with the city's.
DO $$
DECLARE
  missing text[];
BEGIN
  SELECT array_agg(x ORDER BY x) INTO missing
  FROM (
    SELECT a AS x FROM pipeline.params p, unnest(p.outskirts_areas) a
    WHERE NOT EXISTS (SELECT 1 FROM pipeline.district d WHERE d.id = a AND d.kind = 'neighbourhood')
    UNION ALL
    SELECT n FROM pipeline.params p, unnest(p.outskirts_streets) n
    WHERE NOT EXISTS (SELECT 1 FROM pipeline.street s WHERE s.norm_name = pipeline.normalise_name(n))
  ) m;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'outskirts not found: %', missing;
  END IF;
END $$;

-- Tier A skeleton, B grid, C the rest. Ring: 2 km bands round `centre`. Bank: the side of `river`
-- the centroid lies on, L when left of the flow. Chunk: the neighbourhood holding most of the
-- street's length; a street in none goes to the nearest neighbourhood. Outskirts: its chunk is one
-- of `outskirts_areas`, or its name one of `outskirts_streets`.
CREATE TABLE pipeline.street_learning AS
WITH place AS (
  SELECT ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(p.river), 4326), p.utm_srid) AS river,
         ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(p.centre), 4326), p.utm_srid) AS centre,
         p.outskirts_areas,
         ARRAY(SELECT pipeline.normalise_name(n) FROM unnest(p.outskirts_streets) n) AS outskirts_names
  FROM pipeline.params p
),
street AS (
  SELECT s.key, s.road_class, s.norm_name, s.geom, ST_Centroid(s.geom) AS c, place.*,
         ST_LineLocatePoint(place.river, ST_Centroid(s.geom)) AS f
  FROM pipeline.street s, place
)
SELECT s.key,
       CASE
         WHEN s.road_class IN ('motorway', 'trunk', 'primary') THEN 'A'
         WHEN s.road_class IN ('secondary', 'tertiary') THEN 'B'
         ELSE 'C'
       END AS tier,
       floor(ST_Distance(s.c, s.centre) / 2000)::int AS ring,
       CASE
         WHEN (ST_X(flow.b) - ST_X(flow.a)) * (ST_Y(s.c) - ST_Y(flow.a))
            - (ST_Y(flow.b) - ST_Y(flow.a)) * (ST_X(s.c) - ST_X(flow.a)) > 0 THEN 'L'
         ELSE 'R'
       END AS bank,
       chunk.id AS chunk_id,
       coalesce(chunk.id = ANY (s.outskirts_areas), false)
         OR s.norm_name = ANY (s.outskirts_names) AS outskirts
FROM street s
CROSS JOIN LATERAL (
  SELECT ST_LineInterpolatePoint(s.river, greatest(s.f - 1e-4, 0)) AS a,
         ST_LineInterpolatePoint(s.river, least(s.f + 1e-4, 1)) AS b
) flow
LEFT JOIN LATERAL (
  SELECT d.id
  FROM pipeline.district d
  WHERE d.kind = 'neighbourhood'
  ORDER BY CASE WHEN d.geom && s.geom THEN ST_Length(ST_Intersection(s.geom, d.geom)) ELSE 0 END DESC,
           ST_Distance(s.c, d.geom),
           d.id
  LIMIT 1
) chunk ON true;

CREATE UNIQUE INDEX ON pipeline.street_learning (key);

-- A smaller area's raion: the district holding its centre (the nearest one at the city's edge).
CREATE TABLE pipeline.area_parent AS
SELECT a.id, raion.id AS parent_id
FROM pipeline.district a
JOIN pipeline.pack_area pa USING (id)
CROSS JOIN pipeline.params p
CROSS JOIN LATERAL (
  SELECT d.id
  FROM pipeline.district d
  WHERE d.kind = 'district'
  ORDER BY ST_Distance(d.geom, ST_Transform(pa.center, p.utm_srid)), d.id
  LIMIT 1
) raion
WHERE a.kind <> 'district';

-- Neighbourhoods whose boundaries come within 50 m, both ways round.
CREATE TABLE pipeline.chunk_neighbour AS
SELECT a.id AS chunk_a, b.id AS chunk_b
FROM pipeline.district a
JOIN pipeline.district b ON a.id <> b.id AND ST_DWithin(a.geom, b.geom, 50)
WHERE a.kind = 'neighbourhood' AND b.kind = 'neighbourhood';

-- Families: "<prefix> <Roman numeral> <შესახვევი | ჩიხი | გასასვლელი>" is a child of the nearest
-- street its prefix names. A street's children start with its name minus the type word ("ავთო
-- ვარაზის ქუჩა" → "ავთო ვარაზის") or with its last word in the genitive ("… გზატკეცილი" →
-- "… გზატკეცილის", "… ქუჩა" → "… ქუჩის", "… I შესახვევი" → "… I შესახვევის" for a lane's own
-- children). A child more than 1.5 km from its parent is an orphan.
CREATE FUNCTION pipeline.roman(numeral text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT n FROM generate_series(1, 399) n WHERE to_char(n, 'FMRN') = upper(numeral)
$$;

CREATE TABLE pipeline.family_prefix AS
SELECT key, regexp_replace(norm_name, '\s+\S+$', '') AS prefix
FROM pipeline.street
WHERE norm_name ~ '\s'
UNION
SELECT key, regexp_replace(norm_name, '[ია]$', 'ის')
FROM pipeline.street
WHERE norm_name ~ '[ია]$';

CREATE INDEX ON pipeline.family_prefix (prefix);

CREATE TABLE pipeline.family AS
SELECT DISTINCT ON (c.key)
       c.key AS child_key,
       fp.key AS parent_key,
       c.kind,
       c.n,
       ST_Distance(ST_Centroid(cs.geom), ps.geom) AS away_m,
       ST_Distance(ST_Centroid(cs.geom), ps.geom) > 1500 AS orphan
FROM (
  SELECT s.key,
         m[1] AS prefix,
         pipeline.roman(m[2]) AS n,
         CASE m[3] WHEN 'შესახვევი' THEN 'lane' WHEN 'ჩიხი' THEN 'dead_end' ELSE 'passage' END AS kind
  FROM pipeline.street s,
       regexp_match(s.norm_name, '^(.+?)\s+([ivxlc]+)\s+(შესახვევი|ჩიხი|გასასვლელი)$') m
) c
JOIN pipeline.family_prefix fp ON fp.prefix = c.prefix AND fp.key <> c.key
JOIN pipeline.street cs ON cs.key = c.key
JOIN pipeline.street ps ON ps.key = fp.key
WHERE c.n IS NOT NULL
ORDER BY c.key, ST_Distance(cs.geom, ps.geom), fp.key;
