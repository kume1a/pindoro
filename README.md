# Pindoro · პინდორო

Learn a city's streets: see a street name, drop a pin on an unlabelled map, get scored by how far
you were from the real street. First city: Tbilisi.

## Quick start

Prerequisites: Flutter ≥ 3.38 (Dart ≥ 3.10), Node 24 + pnpm 10, Docker, [just](https://just.systems)
and, for running the app, an Android emulator or iOS simulator.

```sh
cp .env.example .env     # only needed for production compose
just setup               # pnpm install + melos bootstrap
just dev                 # PostGIS, API on :3000, Martin tiles on :3001, packs on :8080
just tiles               # once: Georgia vector tiles (+ map styles)
just run-mobile          # Android emulator reaches the host via 10.0.2.2
```

`just fixture` rebuilds the Vake fixture pack bundled with the app from fresh OSM data;
`just test` runs every suite. See `CLAUDE.md` for the repo map, rules and all commands,
`docs/deploy.md` for the home-server deployment and `docs/pack-format.md` for the pack contract.

## Licences

Code: all rights reserved (`LICENSE`). Map data © OpenStreetMap contributors, ODbL 1.0
(`data/LICENSE-ODbL.md`). Tiles: Protomaps basemap from OpenStreetMap. Font: FiraGO, SIL OFL 1.1.
