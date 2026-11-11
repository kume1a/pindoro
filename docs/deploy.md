# Deploying Pindoro

Everything runs with Docker Compose on one Ubuntu home server, next to whatever else runs there.
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
(nightly `pg_dump`), and `pipeline` (profile, run on demand).

All commands below run from the repo root on the server. Shorthand used here:

```sh
alias dc='docker compose --env-file .env -f infra/docker-compose.prod.yml'
```

## 1. Server prerequisites

- Ubuntu Server, x86_64, ≥ 4 GB RAM, ≥ 20 GB free disk (Georgia extract ~200 MB, PostGIS working
  set, `georgia.pmtiles` a few hundred MB, packs).
- Docker Engine + Compose plugin (`curl -fsSL https://get.docker.com | sudo sh`), your user in the
  `docker` group.
- `sudo apt install git just rsync jq` (on Ubuntu 22.04, install `just` from
  <https://just.systems> instead).
- A domain on Cloudflare and a remotely managed tunnel already running on the host, whose
  `cloudflared` reaches host ports through `host.docker.internal`.
- Optional: a second disk mounted at `/mnt/backup` for backup copies.

## 2. Public hostname

One hostname, `PUBLIC_HOST`, e.g. `pindoro.example.com`: the API answers at its root, tiles under
`/tiles` and packs under `/packs`. In the Zero Trust dashboard → **Networks → Tunnels** → the
host's tunnel → **Edit** → **Public hostnames** (newer dashboards: **Published application
routes**), add one route: type **HTTP**, URL `host.docker.internal:8100` (the `HTTP_PORT`).
Cloudflare creates the DNS record; don't add it by hand.

Optional: a **Cache Rule** for paths starting with `/packs/` and `/tiles/` ("Eligible for cache",
respect origin `Cache-Control`). Cloudflare does not cache `.sqlite.gz` or tile paths by default;
Caddy already sends `immutable` for versioned packs and `max-age=60` for `catalog.json` /
`manifest.json`.

## 3. Continuous deployment

[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) deploys every push to the
**`prod`** branch on a self-hosted runner on the server. CI runs on `main`; merging `main` into
`prod` once it is green is a release. The workflow works in the server's checkout at
`/opt/pindoro` (not a runner workspace, which `actions/checkout` cleans): it writes `.env` from
the repository variables, runs `just deploy` (`git pull --ff-only` + `compose up -d --build`),
waits for `https://$PUBLIC_HOST/health` through the tunnel and prunes superseded images.

**Checkout.** The runner's user must own it:

```sh
sudo mkdir -p /opt/pindoro && sudo chown "$USER" /opt/pindoro
git clone -b prod https://github.com/kume1a/pindoro /opt/pindoro
```

**Runner.** Runners belong to one repository, so this is a second one next to any other repo's:
repository → **Settings → Actions → Runners → New self-hosted runner** (Linux, x64), then run the
commands it shows in a new directory such as `~/actions-runner-pindoro`, and install it as a
service so deploys survive a reboot:

```sh
sudo ./svc.sh install && sudo ./svc.sh start
```

**Fork pull requests.** The repository is public and anyone can open a pull request whose
workflow targets `self-hosted`. Under **Settings → Actions → General → Approval for running fork
pull request workflows**, pick **Require approval for all external contributors**, and never
approve a fork's run that changes `.github/workflows`.

**Variables.** Repository → **Settings → Secrets and variables → Actions → Variables**. Every
variable becomes a line of `.env` on each deploy (see `.env.example`):

| Variable            | Value                                                           |
| ------------------- | --------------------------------------------------------------- |
| `PUBLIC_HOST`       | `pindoro.example.com`                                           |
| `POSTGRES_USER`     | `pindoro`                                                       |
| `POSTGRES_PASSWORD` | `openssl rand -hex 24`: it goes into a connection URL, keep hex |
| `POSTGRES_DB`       | `pindoro`                                                       |
| `HTTP_PORT`         | only if 8100 is taken; change the tunnel route with it          |
| `APP_BUILD`         | the newest sideload build (§ 9), once there is one              |
| `APP_URL`           | its APK link (§ 9)                                              |

Variables stay readable in the GitHub UI, so the configuration is recoverable; the workflow never
echoes them. PostGIS publishes no port, so its password never leaves the server's Docker network.

## 4. First deploy

Push `prod` (or run the workflow by hand); once it is green, on the server, once:

```sh
cd /opt/pindoro
just server-setup
```

It runs `just deploy` again, installs the systemd units from `infra/systemd/` and enables their
timers (sections 6 and 7), downloads the Georgia tiles, restarts Martin and builds the first
Tbilisi pack by starting `pindoro-packs.service`. It asks for your sudo password and waits for the
pack build, so run it in `tmux`. Then check:

```sh
dc ps                                            # all up, postgis healthy
curl https://pindoro.example.com/health
curl https://pindoro.example.com/tiles/georgia   # TileJSON
curl https://pindoro.example.com/v1/catalog      # lists tbilisi
journalctl -u pindoro-packs.service              # the first pack's build log
```

The API runs its database migrations on start. Swagger UI (`/docs`) is disabled in production.

## 5. Tiles and packs by hand

The same steps `just server-setup` and the pack timer run:

```sh
dc run --rm pipeline tiles             # pmtiles extract of Protomaps daily build -> infra/tiles/georgia.pmtiles
dc restart martin                      # martin discovers pmtiles files at startup
curl https://pindoro.example.com/tiles/georgia

dc run --rm pipeline fetch tbilisi     # Geofabrik extract into the pipeline cache volume
dc run --rm pipeline build tbilisi     # osm2pgsql + SQL steps + export pack
dc run --rm pipeline validate tbilisi  # schema, districts, >= 30 expert streets each, geometry
dc run --rm pipeline publish tbilisi   # copy pack + manifest into PACKS_DIR, commit street ids, rewrite catalog.json
curl https://pindoro.example.com/v1/catalog
```

`build` stages the new stable street ids in `apps/pipeline/out/tbilisi/identity.json`; only `publish`
writes them to `data/cities/tbilisi/identity.json`, just before the pack goes live, so a build that
fails `validate` never retires an id. Commit the file back so the ids survive:
`git add data/cities && git commit -m "data: refresh tbilisi identity"` and push.

## 6. Monthly pack refresh (systemd timer)

`infra/systemd/pindoro-packs.service` rebuilds the pipeline image, then fetches, builds, validates
and publishes Tbilisi; `pindoro-packs.timer` runs it on the 2nd of each month at 04:00.
`just server-setup` installs and enables both.

```sh
systemctl list-timers pindoro-packs.timer
sudo systemctl start pindoro-packs.service && journalctl -u pindoro-packs.service -f   # manual run
```

`ExecStart` lines run in order and stop at the first failure, so a broken build never gets
published. The last one copies the published street ids to
`infra/backups/tbilisi-identity-YYYY-MM-DD.json`, which the backup copy (§ 7) takes along. Still
commit them back after each run (§ 5): until then the only copies are on this machine. If a later
deploy refuses to pull because `identity.json` changed both here and upstream, keep the
newer ids, never the older ones. Old pack versions stay on disk (immutable URLs); prune them by hand when space matters.
After editing a unit in the repo, copy it again and `sudo systemctl daemon-reload`.

## 7. Backups

The `backup` service writes `infra/backups/pindoro-YYYY-MM-DD.dump` (`pg_dump -Fc`) every night at
03:00 UTC and deletes dumps older than 14 days. `infra/systemd/pindoro-backup-copy.timer` copies
them to `/mnt/backup/pindoro` daily at 04:00 UTC and keeps 90 days there (installed by
`just server-setup`).

`ConditionPathIsMountPoint` skips the copy when the disk is not mounted instead of filling the
root filesystem. `.env` is rebuilt from the repository variables on every deploy.

### Restore

```sh
dc stop api
dc exec -T postgis pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
  < infra/backups/pindoro-2026-11-05.dump
dc start api
```

Packs and tiles are rebuilt from OSM data (steps 5); only the database and
`data/cities/*/identity.json` (in git) need backing up. To recover lost street ids, copy the newest
`infra/backups/tbilisi-identity-*.json` (or its copy in `/mnt/backup/pindoro`) to
`data/cities/tbilisi/identity.json` and commit it before the next pack refresh.

## 8. Updating

Merge `main` into `prod`; the Deploy workflow does the rest. By hand on the server:

```sh
just deploy                      # pulls, rebuilds the api image, recreates changed services
dc logs -f api caddy
```

## 9. Sideload builds

No App Store or Play Store release is planned: friends install an APK directly. The app reads its
server URLs at build time; `just release` points them at `PUBLIC_HOST` over HTTPS.
Bump `version` in `apps/mobile/pubspec.yaml` first: Android refuses to install a lower build number
over an installed app.

**Android.** Create the signing key once and keep it, with its passwords, outside the repo; an APK
signed with a different key can't update an installed app, so every friend would have to uninstall
(and lose their progress) first:

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

```sh
just release apk pindoro.example.com
# → apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

Without `key.properties` the APK is signed with the debug key of the machine that built it, so
builds from another machine can't update it.

**Offering the build.** Installed apps never update themselves; the catalog tells them a newer
build is out. Put the APK next to the packs and point the variables at it, where `APP_BUILD` is the
`+N` of `version`:

```sh
scp apps/mobile/build/app/outputs/flutter-apk/app-release.apk server:/opt/pindoro/infra/packs/app/pindoro-2.apk
```

Then set the repository variables `APP_BUILD=2` and
`APP_URL=https://pindoro.example.com/packs/app/pindoro-2.apk` and run the Deploy workflow.

Older installs then offer the download at launch, and Settings → About shows each install's
version and build. Raise `APP_BUILD` with every build you hand out, so nobody stays behind on a
build that a new pack format or API change has left broken.

**iOS** is not distributed. If ever needed, an ad-hoc build
(`just release ipa pindoro.example.com`) needs an Apple Developer
account and each device's UDID registered; CI builds iOS unsigned on every push.
