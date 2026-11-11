# Deploying Pindoro

Everything runs with Docker Compose on one Ubuntu home server, next to whatever else runs there,
and is driven by one GitHub Actions workflow on a self-hosted runner on that server. Nothing is set
up on the server by hand beyond Docker and the runner.

Cloudflare terminates TLS, and the host's own remotely managed Cloudflare Tunnel (a `cloudflared`
that lives outside this repo and serves the server's other sites too) carries traffic to Caddy;
**no ports are opened on the router**. Caddy is the only service published on the host
(`HTTP_PORT`, default 8100); the rest sit on an internal-only Docker network, and only Caddy and
one-off `pipeline` runs can reach the internet.

```
internet ─▶ Cloudflare (TLS, DNS) ─▶ host tunnel ─▶ host:HTTP_PORT ─▶ caddy:80   (PUBLIC_HOST)
                                                    ├─ /tiles/* ─▶ martin:3000  (PMTiles vector tiles)
                                                    ├─ /packs/* ─▶ file_server  (city packs, catalog.json)
                                                    └─ /*       ─▶ api:3000     (Fastify + PostGIS)
```

Services in `infra/docker-compose.prod.yml`: `postgis`, `api`, `martin`, `caddy`, `backup`
(nightly), and `pipeline` (profile, run by the workflow). All state lives in Docker volumes of the
`pindoro` project, never in the checkout: `pindoro_pgdata`, `pindoro_packs` (packs, `catalog.json`,
the live street ids, sideload APKs), `pindoro_tiles`, `pindoro_backups`.

## 1. Server prerequisites

- Ubuntu Server, x86_64, ≥ 4 GB RAM, ≥ 20 GB free disk (Georgia extract ~200 MB, PostGIS working
  set, `georgia.pmtiles` a few hundred MB, packs).
- Docker Engine + Compose plugin (`curl -fsSL https://get.docker.com | sudo sh`), and
  `sudo apt install jq curl`.
- A domain on Cloudflare and a remotely managed tunnel already running on the host, whose
  `cloudflared` reaches host ports through `host.docker.internal`.

## 2. Public hostname

One hostname, `PUBLIC_HOST`, e.g. `pindoro.example.com`: the API answers at its root, tiles under
`/tiles` and packs under `/packs`. In the Cloudflare dashboard → **Networking → Tunnels** → the
host's tunnel → **Routes** → **Add route** → **Published application**: type **HTTP**, URL
`host.docker.internal:8100` (the `HTTP_PORT`). Cloudflare creates the DNS record; don't add it by
hand, and don't leave an old record pointing at another tunnel (that answers 530, error 1033).

Optional: a **Cache Rule** for paths starting with `/packs/` and `/tiles/` ("Eligible for cache",
respect origin `Cache-Control`). Caddy already sends `immutable` for versioned packs and
`max-age=60` for `catalog.json` / `manifest.json`.

## 3. GitHub

**Runner.** Repository → **Settings → Actions → Runners → New self-hosted runner** (Linux, x64).
Runners belong to one repository, so use a new directory next to any other repo's runner; run the
commands GitHub shows as a user in the `docker` group, then install it as a service so it survives
reboots:

```sh
sudo ./svc.sh install && sudo ./svc.sh start
```

The repository is public, so anyone can open a pull request whose workflow targets `self-hosted`;
GitHub only asks for approval before running workflows from outside contributors.

**Variables.** Repository → **Settings → Secrets and variables → Actions → Variables**. Every
variable becomes a line of `.env` on each run (see `.env.example`):

| Variable            | Value                                                           |
| ------------------- | --------------------------------------------------------------- |
| `PUBLIC_HOST`       | `pindoro.example.com`                                           |
| `POSTGRES_USER`     | `pindoro`                                                       |
| `POSTGRES_PASSWORD` | `openssl rand -hex 24`: it goes into a connection URL, keep hex |
| `POSTGRES_DB`       | `pindoro`                                                       |
| `HTTP_PORT`         | only if 8100 is taken; change the tunnel route with it          |
| `APP_BUILD`         | the newest sideload build (§ 7), once there is one              |
| `APP_URL`           | its APK link (§ 7)                                              |

Variables stay readable in the GitHub UI, so the configuration is recoverable; the workflow never
echoes them. PostGIS publishes no port, so its password never leaves the server's Docker network.

## 4. The Deploy workflow

[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) always runs the code on `prod`.
CI runs on `main`; merging `main` into `prod` once it is green is a release. Each run writes `.env`
from the variables, starts the stack (`compose up -d --build`), waits for
`https://$PUBLIC_HOST/health` through the tunnel, then fills in what is missing:

- **A push to `prod`** deploys, downloads the Georgia tiles if Martin has none, and builds and
  publishes every city under `data/cities/` that has no pack yet. A new server, or a new city, needs
  nothing else: add `data/cities/<city>/city.yaml` (see the pipeline's `CLAUDE.md`), merge it to
  `prod`, and its first pack goes live. A city outside Georgia also needs its own tiles and app map
  style.
- **On the 2nd of each month** (00:00 UTC) it rebuilds every city's pack from a fresh Geofabrik
  extract: fetch, build, validate, publish. A failed step stops before publishing, so the previous
  pack stays live, and GitHub emails you about the failed run. GitHub pauses schedules in public
  repositories after 60 days without activity; it emails first, and one click turns it back on.
- **Actions → Deploy → Run workflow** rebuilds the packs you name (`missing`, `all` or a city id)
  and, when ticked, downloads the tiles again.

Runs never overlap and are never cancelled midway. Old pack versions stay in the packs volume
(immutable URLs); prune them by hand when space matters.

## 5. Street ids

A street's id must never change: the app stores progress against it. The live ids of a city sit
next to its packs, in `pindoro_packs` at `<city>/identity.json` (served at
`https://$PUBLIC_HOST/packs/<city>/identity.json`). The first build seeds them from the committed
`data/cities/<city>/identity.json`; from then on each build matches, retires and adds ids against
the live file, and `publish` writes the new ids just before the pack goes live, so a build that
fails `validate` changes nothing. The app's bundled Vake fixture must use the same ids:
`just fixture <host>` downloads them into `data/` first, then commit the result with the fixture.

## 6. Backups

The `backup` service writes `pindoro-YYYY-MM-DD.dump` (`pg_dump -Fc`) and
`<city>-identity-YYYY-MM-DD.json` into `pindoro_backups` every night at 03:00 UTC and deletes files
older than 14 days. Everything else is rebuilt from OSM data by the workflow.

```sh
docker exec pindoro-backup-1 ls /backups

# Restore the database
docker stop pindoro-api-1
docker exec pindoro-backup-1 sh -c 'pg_restore --clean --if-exists -d "$PGDATABASE" /backups/pindoro-2026-11-05.dump'
docker start pindoro-api-1

# Restore a city's street ids
docker run --rm -v pindoro_backups:/b:ro -v pindoro_packs:/p alpine \
  cp /b/tbilisi-identity-2026-11-05.json /p/tbilisi/identity.json
```

Logs: `docker logs -f pindoro-api-1` (or `-caddy-1`, `-martin-1`, `-backup-1`).

## 7. Sideload builds

No App Store or Play Store release is planned: friends install an APK directly. The app reads its
server URLs at build time; `just release apk <PUBLIC_HOST>` points them at the API and tiles over
HTTPS. Bump `version` in `apps/mobile/pubspec.yaml` first: Android refuses to install a lower build
number over an installed app.

**Signing.** Create the key once and keep it, with its passwords, outside the repo; an APK signed
with a different key can't update an installed app, so every friend would have to uninstall (and
lose their progress) first:

```sh
keytool -genkeypair -keystore ~/pindoro-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Then write `apps/mobile/android/key.properties` (gitignored):

```properties
storeFile=/home/you/pindoro-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without `key.properties` the APK is signed with the debug key of the machine that built it, so
builds from another machine can't update it.

**Offering the build.** Installed apps never update themselves; the catalog tells them a newer
build is out. Copy the APK into the packs volume on the server, where `2` is the `+N` of `version`:

```sh
docker run --rm -v pindoro_packs:/packs -v "$PWD:/src:ro" alpine \
  sh -c 'mkdir -p /packs/app && cp /src/app-release.apk /packs/app/pindoro-2.apk'
```

Then set the variables `APP_BUILD=2` and `APP_URL=https://pindoro.example.com/packs/app/pindoro-2.apk`
and run the Deploy workflow. Older installs offer the download at launch, and Settings → About shows
each install's version and build. Raise `APP_BUILD` with every build you hand out, so nobody stays
behind on a build that a new pack format or API change has left broken.

**iOS** is not distributed. If ever needed, an ad-hoc build (`just release ipa pindoro.example.com`)
needs an Apple Developer account and each device's UDID registered; CI builds iOS unsigned on every
push.
