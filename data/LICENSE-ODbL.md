# OpenStreetMap data licence

The following files are derived from OpenStreetMap data and are a Derivative Database of it:

- `data/cities/*/identity.json` (street names and OSM way ids)
- `apps/mobile/assets/packs_fixture/*.sqlite` (city packs: boundaries, street names and geometry)
- every city pack published by `pipeline publish`

**© OpenStreetMap contributors.** OpenStreetMap data is available under the
[Open Database License 1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/); see
<https://www.openstreetmap.org/copyright>. These derived databases are made available under the same
ODbL 1.0. Any rights in individual contents of the database are licensed under the
[Database Contents License](https://opendatacommons.org/licenses/dbcl/1-0/).

Attribution required wherever the data is shown: "© OpenStreetMap contributors". The app shows
"© OpenStreetMap contributors, Protomaps" on every map (basemap tiles: Protomaps builds of
OpenStreetMap data, same licence).

The source extract is Geofabrik's Georgia extract (<https://download.geofabrik.de/europe/georgia.html>);
the exact OSM timestamp of each pack is stored in its `meta.osm_timestamp` and `manifest.json`.
