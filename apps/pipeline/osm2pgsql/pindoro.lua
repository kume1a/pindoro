-- osm2pgsql flex config: loads only what the pipeline needs into schema `osm`.
-- Uses the geometry API (osm2pgsql >= 1.7); tested with 1.8 (Debian bookworm) and 1.11 (Ubuntu 24.04).

local schema = 'osm'

local function names(columns)
    table.insert(columns, { column = 'name', type = 'text' })
    table.insert(columns, { column = 'name_ka', type = 'text' })
    table.insert(columns, { column = 'name_en', type = 'text' })
    return columns
end

local function name_values(tags, row)
    row.name = tags.name
    row.name_ka = tags['name:ka']
    row.name_en = tags['name:en']
    return row
end

local roads = osm2pgsql.define_table({
    name = 'roads',
    schema = schema,
    ids = { type = 'way', id_column = 'way_id' },
    columns = names({
        { column = 'highway', type = 'text', not_null = true },
        { column = 'access', type = 'text' },
        { column = 'etymology', type = 'text' },
        -- One-way travel and roundabouts, for the directed graph; bridges for bridge items.
        { column = 'oneway', type = 'text' },
        { column = 'junction', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'bridge_name', type = 'text' },
        -- Comma-separated node ids, for the road graph's junctions (text works on 1.8 and 1.11).
        { column = 'nodes', type = 'text', not_null = true },
        { column = 'geom', type = 'linestring', projection = 4326, not_null = true },
    }),
})

local boundaries = osm2pgsql.define_table({
    name = 'boundaries',
    schema = schema,
    ids = { type = 'relation', id_column = 'relation_id' },
    columns = names({
        { column = 'boundary', type = 'text' },
        { column = 'admin_level', type = 'text' },
        { column = 'place', type = 'text' },
        { column = 'geom', type = 'multipolygon', projection = 4326 },
    }),
})

local subareas = osm2pgsql.define_table({
    name = 'subareas',
    schema = schema,
    ids = { type = 'relation', id_column = 'parent_id' },
    columns = {
        { column = 'child_id', type = 'bigint', not_null = true },
        { column = 'role', type = 'text', not_null = true },
    },
})

local places = osm2pgsql.define_table({
    name = 'places',
    schema = schema,
    ids = { type = 'node', id_column = 'node_id' },
    columns = names({
        { column = 'place', type = 'text', not_null = true },
        { column = 'geom', type = 'point', projection = 4326, not_null = true },
    }),
})

-- Quarters and neighbourhoods drawn as areas (closed ways or multipolygon relations).
local place_areas = osm2pgsql.define_table({
    name = 'place_areas',
    schema = schema,
    ids = { type = 'any', id_column = 'osm_id', type_column = 'osm_type' },
    columns = names({
        { column = 'place', type = 'text', not_null = true },
        { column = 'geom', type = 'geometry', projection = 4326, not_null = true },
    }),
})

-- Turn restrictions with a node as `via` (way-via restrictions are left out), for cars.
local restrictions = osm2pgsql.define_table({
    name = 'restrictions',
    schema = schema,
    ids = { type = 'relation', id_column = 'relation_id' },
    columns = {
        { column = 'restriction', type = 'text', not_null = true },
        { column = 'from_way', type = 'bigint', not_null = true },
        { column = 'via_node', type = 'bigint', not_null = true },
        { column = 'to_way', type = 'bigint', not_null = true },
    },
})

-- Landmark candidates (SPEC §9): their kind, brand and the tags behind salience.
local pois = osm2pgsql.define_table({
    name = 'pois',
    schema = schema,
    ids = { type = 'any', id_column = 'osm_id', type_column = 'osm_type' },
    columns = names({
        { column = 'kind', type = 'text', not_null = true },
        { column = 'brand', type = 'text' },
        { column = 'wiki', type = 'bool' },
        { column = 'levels', type = 'text' },
        { column = 'geom', type = 'geometry', projection = 4326, not_null = true },
    }),
})

local area_places = { quarter = true, neighbourhood = true }

local branded = { bank = true, pharmacy = true, fast_food = true }

-- The landmark kind of an object's tags (SPEC §9), or nil.
local function poi_kind(tags)
    if tags.station == 'subway' or tags.railway == 'station' or tags.railway == 'subway_entrance' then
        return 'metro'
    end
    if tags.place == 'square' then return 'square' end
    local amenity = tags.amenity
    if amenity == 'fuel' then return 'fuel' end
    if amenity == 'place_of_worship' then return 'worship' end
    if tags.shop == 'mall' or tags.shop == 'department_store' then return 'mall' end
    if tags.shop == 'supermarket' then return 'supermarket' end
    if amenity == 'bus_station' or tags.public_transport == 'station' then return 'station' end
    if amenity == 'hospital' or amenity == 'university' then return amenity end
    if tags.historic == 'monument' or tags.historic == 'memorial' then return 'monument' end
    if tags.tourism == 'attraction' then return 'attraction' end
    if tags.man_made == 'tower' then return 'tower' end
    if tags.leisure == 'stadium' or tags.leisure == 'park' then return tags.leisure end
    if branded[amenity] and tags.brand then return amenity end
    return nil
end

local function insert_poi(tags, geom)
    local kind = poi_kind(tags)
    if not kind then return end
    pois:insert(name_values(tags, {
        kind = kind,
        brand = tags.brand,
        wiki = (tags.wikidata or tags.wikipedia) ~= nil,
        levels = tags['building:levels'],
        geom = geom,
    }))
end

function osm2pgsql.process_node(object)
    local tags = object.tags
    if tags.place then
        places:insert(name_values(tags, { place = tags.place, geom = object:as_point() }))
    end
    insert_poi(tags, object:as_point())
end

function osm2pgsql.process_way(object)
    local tags = object.tags
    if tags.highway then
        roads:insert(name_values(tags, {
            highway = tags.highway,
            access = tags.access,
            etymology = tags['name:etymology'],
            oneway = tags.oneway,
            junction = tags.junction,
            bridge = tags.bridge,
            bridge_name = tags['bridge:name'],
            nodes = table.concat(object.nodes, ','),
            geom = object:as_linestring(),
        }))
    end
    if area_places[tags.place] and object.is_closed then
        place_areas:insert(name_values(tags, { place = tags.place, geom = object:as_polygon() }))
    end
    if not tags.highway then
        insert_poi(tags, object.is_closed and object:as_polygon() or object:as_linestring())
    end
end

-- A car's turn restriction: `restriction:motorcar` wins over `restriction`; one excepting cars
-- is skipped.
local function process_restriction(object)
    local tags = object.tags
    local kind = tags['restriction:motorcar'] or tags.restriction
    if not kind or (tags.except and tags.except:find('motorcar')) then return end
    local from, via, to
    for _, member in ipairs(object.members) do
        if member.role == 'from' and member.type == 'w' then from = from and -1 or member.ref end
        if member.role == 'to' and member.type == 'w' then to = to and -1 or member.ref end
        if member.role == 'via' then via = (member.type == 'n' and not via) and member.ref or -1 end
    end
    if from and to and via and from > 0 and to > 0 and via > 0 then
        restrictions:insert({ restriction = kind, from_way = from, via_node = via, to_way = to })
    end
end

function osm2pgsql.process_relation(object)
    local tags = object.tags
    if tags.type == 'restriction' then return process_restriction(object) end
    if tags.type == 'multipolygon' then insert_poi(tags, object:as_multipolygon()) end
    if tags.type ~= 'boundary' and tags.type ~= 'multipolygon' then return end
    if not (tags.boundary or tags.place) then return end

    if area_places[tags.place] then
        place_areas:insert(name_values(tags, { place = tags.place, geom = object:as_multipolygon() }))
    end

    boundaries:insert(name_values(tags, {
        boundary = tags.boundary,
        admin_level = tags.admin_level,
        place = tags.place,
        geom = object:as_multipolygon(),
    }))

    for _, member in ipairs(object.members) do
        if member.type == 'r' and member.role == 'subarea' then
            subareas:insert({ child_id = member.ref, role = member.role })
        end
    end
end
