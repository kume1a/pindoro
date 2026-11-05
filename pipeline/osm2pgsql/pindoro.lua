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

function osm2pgsql.process_node(object)
    local tags = object.tags
    if tags.place then
        places:insert(name_values(tags, { place = tags.place, geom = object:as_point() }))
    end
end

function osm2pgsql.process_way(object)
    local tags = object.tags
    if tags.highway then
        roads:insert(name_values(tags, {
            highway = tags.highway,
            access = tags.access,
            geom = object:as_linestring(),
        }))
    end
end

function osm2pgsql.process_relation(object)
    local tags = object.tags
    if tags.type ~= 'boundary' and tags.type ~= 'multipolygon' then return end
    if not (tags.boundary or tags.place) then return end

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
