# Deploying Pindoro

Everything runs with Docker Compose on one Ubuntu home server. Cloudflare terminates TLS and a
token-based Cloudflare Tunnel (`cloudflared`) carries traffic to Caddy; **no ports are opened on the
router or published on the host**. Services sit on an internal-only Docker network; only
`cloudflared` and one-off `pipeline` runs can reach the internet.

```
internet ─▶ Cloudflare (TLS, DNS) ─▶ tunnel ─▶ cloudflared ─▶ caddy:80
                                                  ├─ api.$DOMAIN   ─▶ api:3000     (Fastify + PostGIS)
                                                  ├─ tiles.$DOMAIN ─▶ martin:3000  (PMTiles vector tiles)
                                                  └─ packs.$DOMAIN ─▶ file_server  (city packs, catalog.json)
```

Services in `infra/docker-compose.prod.yml`: `postgis`, `api`, `martin`, `caddy`, `cloudflared`,
`backup` (nightly `pg_dump`), and `pipeline` (profile, run on demand).

All commands below run from the repo root. Shorthand used here:

```sh
alias dc='docker compose --env-file .env -f infra/docker-compose.prod.yml'
```

## 1. Server prerequisites

- Ubuntu Server 24.04 LTS, x86_64, ≥ 4 GB RAM, ≥ 20 GB free disk (Georgia extract ~200 MB,
  PostGIS working set, `georgia.pmtiles` a few hundred MB, packs).
- Docker Engine + Compose plugin from Docker's apt repository
  (<https://docs.docker.com/engine/install/ubuntu/>), your user in the `docker` group.
- `sudo apt install git just rsync`.
- A domain whose DNS is managed by Cloudflare.
- Optional: a second disk mounted at `/mnt/backup` for backup copies.

## 2. Clone and configure

```sh
sudo mkdir -p /opt/pindoro && sudo chown "$USER" /opt/pindoro
git clone <repo-url> /opt/pindoro && cd /opt/pindoro
cp .env.example .env && chmod 600 .env
```

Edit `.env`:

| Variable                    | Value                                                             |
| --------------------------- | ----------------------------------------------------------------- |
| `DOMAIN`                    | e.g. `pindoro.app` → serves `api.`, `tiles.`, `packs.` subdomains |
| `POSTGRES_USER/PASSWORD/DB` | strong password; never reuse the dev defaults                     |
| `CLOUDFLARE_TUNNEL_TOKEN`   | from step 3                                                       |
| `PACKS_DIR`, `TILES_DIR`    | host dirs, relative to `infra/` (defaults `./packs`, `./tiles`)   |

## 3. Cloudflare Tunnel

1. Cloudflare dashboard → **Zero Trust → Networks → Tunnels → Create a tunnel** → type
   **Cloudflared** → name it `pindoro`.
2. On the "Install connector" step pick Docker and copy only the token (the long string after
   `--token`) into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`. Don't run the shown command; compose runs
   `cloudflared` for you.
3. **Public hostnames** (Cloudflare creates the DNS records):

   | Subdomain | Domain    | Service type | URL        |
   | --------- | --------- | ------------ | ---------- |
   | `api`     | `$DOMAIN` | HTTP         | `caddy:80` |
   | `tiles`   | `$DOMAIN` | HTTP         | `caddy:80` |
   | `packs`   | `$DOMAIN` | HTTP         | `caddy:80` |

   Caddy routes by `Host`, so all three point at the same origin.
4. Optional: a **Cache Rule** for `packs.$DOMAIN` and `tiles.$DOMAIN` ("Eligible for cache",
   respect origin `Cache-Control`). Cloudflare does not cache `.sqlite.gz` or tile paths by default;
   Caddy already sends `immutable` for versioned packs and `max-age=60` for `catalog.json` /
   `manifest.json`.

## 4. First deploy

```sh
just server-setup
```

It runs `just deploy` (`git pull` + `docker compose up -d --build`), installs the systemd units
from `infra/systemd/` and enables their timers (sections 6 and 7), downloads the Georgia tiles,
restarts Martin and builds the first Tbilisi pack by starting `pindoro-packs.service`. Then check:

```sh
dc ps                                  # all healthy; cloudflared shows "Registered tunnel connection"
curl https://api.$DOMAIN/health
curl https://tiles.$DOMAIN/georgia     # TileJSON
curl https://api.$DOMAIN/v1/catalog    # lists tbilisi
journalctl -u pindoro-packs.service    # the first pack's build log
```

The API runs its database migrations on start. Swagger UI (`/docs`) is disabled in production.

## 5. Tiles and packs by hand

The same steps `just server-setup` and the pack timer run:

```sh
dc run --rm pipeline tiles             # pmtiles extract of Protomaps daily build -> infra/tiles/georgia.pmtiles
dc restart martin                      # martin discovers pmtiles files at startup
curl https://tiles.$DOMAIN/georgia     # TileJSON

dc run --rm pipeline fetch tbilisi     # Geofabrik extract into the pipeline cache volume
dc run --rm pipeline build tbilisi     # osm2pgsql + SQL steps + export pack
dc run --rm pipeline validate tbilisi  # schema, districts, >= 30 expert streets each, geometry
dc run --rm pipeline publish tbilisi   # copy pack + manifest into PACKS_DIR, commit street ids, rewrite catalog.json
curl https://api.$DOMAIN/v1/catalog
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
`just deploy` refuses to pull because `identity.json` changed both here and upstream, keep the
newer ids, never the older ones. Old pack versions stay on disk (immutable URLs); prune them by hand when space matters.
After editing a unit in the repo, copy it again and `sudo systemctl daemon-reload`.

## 7. Backups

The `backup` service writes `infra/backups/pindoro-YYYY-MM-DD.dump` (`pg_dump -Fc`) every night at
03:00 UTC and deletes dumps older than 14 days. `infra/systemd/pindoro-backup-copy.timer` copies
them to `/mnt/backup/pindoro` daily at 04:00 UTC and keeps 90 days there (installed by
`just server-setup`).

`ConditionPathIsMountPoint` skips the copy when the disk is not mounted instead of filling the
root filesystem. Keep a copy of `.env` somewhere safe too; it is not in git.

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

```sh
just deploy                      # pulls, rebuilds the api image, recreates changed services
dc logs -f api caddy cloudflared
```

## 9. Sideload builds

No App Store or Play Store release is planned: friends install an APK directly. The app reads its
server URLs at build time; `just release` points them at `api.`, `packs.` and `tiles.` of your
domain over HTTPS. Bump `version` in `apps/mobile/pubspec.yaml` first: Android refuses to install a
lower build number over an installed app.

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
just release apk pindoro.app   # → apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

Without `key.properties` the APK is signed with the debug key of the machine that built it, so
builds from another machine can't update it.

**Offering the build.** Installed apps never update themselves; the catalog tells them a newer
build is out. Put the APK next to the packs and point `.env` at it, where `APP_BUILD` is the `+N`
of `version`:

```sh
scp apps/mobile/build/app/outputs/flutter-apk/app-release.apk server:/opt/pindoro/infra/packs/app/pindoro-2.apk
# then on the server, in .env: APP_BUILD=2 and APP_URL=https://packs.pindoro.app/app/pindoro-2.apk
dc up -d api
```

Older installs then offer the download at launch, and Settings → About shows each install's
version and build. Raise `APP_BUILD` with every build you hand out, so nobody stays behind on a
build that a new pack format or API change has left broken.

**iOS** is not distributed. If ever needed, an ad-hoc build (`just release ipa pindoro.app`) needs
an Apple Developer account and each device's UDID registered; CI builds iOS unsigned on every push.
