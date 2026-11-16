-- Directed road graph of the pack's streets and their connector ways (SPEC §2.1, §16.7): a junction
-- is an OSM node two ways share (or one way meets twice), or a way's end; an edge is a way's
-- stretch between two consecutive junctions, carrying the way's one-way rule and bridge. A way
-- whose geometry lost points against its node list (duplicate locations) is skipped, since its
-- points can't be matched to node ids.

CREATE TABLE pipeline.graph_way AS
WITH way AS (
  SELECT s.key AS street_key, r.way_id, r.geom
  FROM pipeline.street s
  CROSS JOIN LATERAL unnest(s.way_ids) AS w(way_id)
  JOIN pipeline.road r ON r.way_id = w.way_id
  UNION ALL
  SELECT NULL, c.way_id, c.geom FROM pipeline.connector c
)
SELECT w.street_key, w.way_id, w.geom, n.nodes,
       pipeline.oneway(o.oneway, o.junction, o.highway) AS oneway,
       CASE WHEN o.bridge IS NOT NULL AND o.bridge <> 'no' THEN o.way_id END AS bridge_way
FROM way w
JOIN osm.roads o ON o.way_id = w.way_id
CROSS JOIN LATERAL (SELECT string_to_array(o.nodes, ',')::bigint[] AS nodes) n
WHERE ST_NPoints(w.geom) = cardinality(n.nodes);

CREATE TABLE pipeline.graph_node AS
SELECT g.way_id, p.pos::int AS pos, p.node_id, cardinality(g.nodes) AS last
FROM pipeline.graph_way g
CROSS JOIN LATERAL unnest(g.nodes) WITH ORDINALITY AS p(node_id, pos);

CREATE INDEX ON pipeline.graph_node (node_id);

CREATE TABLE pipeline.junction AS
SELECT row_number() OVER (ORDER BY node_id) AS id, node_id
FROM pipeline.graph_node
GROUP BY node_id
HAVING count(*) > 1 OR bool_or(pos = 1 OR pos = last);

CREATE UNIQUE INDEX ON pipeline.junction (node_id);

-- Each way's junction positions in order, paired with the next one.
CREATE TABLE pipeline.road_edge AS
WITH cut AS (
  SELECT n.way_id,
         n.pos,
         j.id AS junction,
         lead(n.pos) OVER w AS next_pos,
         lead(j.id) OVER w AS next_junction
  FROM pipeline.graph_node n
  JOIN pipeline.junction j USING (node_id)
  WINDOW w AS (PARTITION BY n.way_id ORDER BY n.pos)
),
stretch AS (
  SELECT g.street_key,
         g.way_id,
         g.oneway,
         g.bridge_way,
         c.junction AS from_junction,
         c.next_junction AS to_junction,
         (SELECT ST_MakeLine(d.geom ORDER BY d.path[1])
          FROM ST_DumpPoints(g.geom) d
          WHERE d.path[1] BETWEEN c.pos AND c.next_pos) AS geom
  FROM cut c
  JOIN pipeline.graph_way g USING (way_id)
  WHERE c.next_pos IS NOT NULL
)
SELECT row_number() OVER (ORDER BY street_key, way_id, from_junction, to_junction) AS id,
       street_key,
       way_id,
       oneway,
       bridge_way,
       from_junction,
       to_junction,
       ST_Length(geom) AS length_m,
       -- ST_Simplify keeps both ends, so an edge still starts and ends at its junctions; edges shorter
       -- than the tolerance are kept rather than collapsed.
       ST_Transform(ST_Simplify(geom, 3, true), 4326) AS geom
FROM stretch
WHERE from_junction <> to_junction AND ST_Length(geom) > 0;

CREATE TABLE pipeline.junction_point AS
SELECT DISTINCT ON (j.id) j.id, ST_Transform(ST_PointN(g.geom, n.pos), 4326) AS geom
FROM pipeline.junction j
JOIN pipeline.graph_node n USING (node_id)
JOIN pipeline.graph_way g USING (way_id)
ORDER BY j.id;

CREATE INDEX ON pipeline.road_edge (way_id);

-- Turn restrictions on the edges that meet at their via node: `no_*` forbids the turn, `only_*`
-- makes it the only one from that edge. As OSM requires, the from and to ways must end at the via
-- node; one whose way runs through it is ambiguous and left out.
CREATE TABLE pipeline.turn_restriction AS
WITH way_end AS (
  SELECT way_id, node_id FROM pipeline.graph_node WHERE pos = 1 OR pos = last
)
SELECT DISTINCT f.id AS from_edge, j.id AS via_junction, t.id AS to_edge,
       r.restriction LIKE 'only\_%' AS is_only
FROM osm.restrictions r
JOIN pipeline.junction j ON j.node_id = r.via_node
JOIN way_end fe ON fe.way_id = r.from_way AND fe.node_id = r.via_node
JOIN way_end te ON te.way_id = r.to_way AND te.node_id = r.via_node
JOIN pipeline.road_edge f ON f.way_id = r.from_way AND j.id IN (f.from_junction, f.to_junction)
JOIN pipeline.road_edge t ON t.way_id = r.to_way AND j.id IN (t.from_junction, t.to_junction)
WHERE r.restriction LIKE 'no\_%' OR r.restriction LIKE 'only\_%';
