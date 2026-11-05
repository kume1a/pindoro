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

| Variable                  | Value                                                                  |
| ------------------------- | ---------------------------------------------------------------------- |
| `DOMAIN`                  | e.g. `pindoro.app` → serves `api.`, `tiles.`, `packs.` subdomains      |
| `POSTGRES_USER/PASSWORD/DB` | strong password; never reuse the dev defaults                        |
| `CLOUDFLARE_TUNNEL_TOKEN` | from step 3                                                            |
| `PACKS_DIR`, `TILES_DIR`  | host dirs, relative to `infra/` (defaults `./packs`, `./tiles`)        |

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
just deploy        # git pull && docker compose -f infra/docker-compose.prod.yml up -d --build
dc ps              # all services healthy; cloudflared shows "Registered tunnel connection"
curl https://api.$DOMAIN/health
```

The API runs its database migrations on start. Swagger UI (`/docs`) is disabled in production.

## 5. Tiles and the first pack

```sh
dc run --rm pipeline tiles             # pmtiles extract of Protomaps daily build -> infra/tiles/georgia.pmtiles
dc restart martin                      # martin discovers pmtiles files at startup
curl https://tiles.$DOMAIN/georgia     # TileJSON

dc run --rm pipeline fetch tbilisi     # Geofabrik extract into the pipeline cache volume
dc run --rm pipeline build tbilisi     # osm2pgsql + SQL steps + export pack
dc run --rm pipeline publish tbilisi   # copy pack + manifest into PACKS_DIR, rewrite catalog.json
curl https://api.$DOMAIN/v1/catalog
```

`build` also updates `data/cities/tbilisi/identity.json` (stable street ids). Commit it back so the
ids survive: `git add data/cities && git commit -m "data: refresh tbilisi identity"` and push.

## 6. Monthly pack refresh (systemd timer)

`/etc/systemd/system/pindoro-packs.service`:

```ini
[Unit]
Description=Pindoro monthly city pack refresh
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/pindoro
ExecStartPre=/usr/bin/docker compose --env-file .env -f infra/docker-compose.prod.yml build pipeline
ExecStart=/usr/bin/docker compose --env-file .env -f infra/docker-compose.prod.yml run --rm pipeline fetch tbilisi
ExecStart=/usr/bin/docker compose --env-file .env -f infra/docker-compose.prod.yml run --rm pipeline build tbilisi
ExecStart=/usr/bin/docker compose --env-file .env -f infra/docker-compose.prod.yml run --rm pipeline publish tbilisi
```

`/etc/systemd/system/pindoro-packs.timer`:

```ini
[Unit]
Description=Run the Pindoro pack refresh monthly

[Timer]
OnCalendar=*-*-02 04:00:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
```

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now pindoro-packs.timer
systemctl list-timers pindoro-packs.timer
sudo systemctl start pindoro-packs.service && journalctl -u pindoro-packs.service -f   # manual run
```

`ExecStart` lines run in order and stop at the first failure, so a broken build never gets
published. Old pack versions stay on disk (immutable URLs); prune them by hand when space matters.

## 7. Backups

The `backup` service writes `infra/backups/pindoro-YYYY-MM-DD.dump` (`pg_dump -Fc`) every night at
03:00 UTC and deletes dumps older than 14 days. Copy them to a second disk with another timer.

`/etc/systemd/system/pindoro-backup-copy.service`:

```ini
[Unit]
Description=Copy Pindoro database dumps to the backup disk
ConditionPathIsMountPoint=/mnt/backup

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /mnt/backup/pindoro
ExecStart=/usr/bin/rsync -a /opt/pindoro/infra/backups/ /mnt/backup/pindoro/
ExecStart=/usr/bin/find /mnt/backup/pindoro -name 'pindoro-*.dump' -mtime +90 -delete
```

`/etc/systemd/system/pindoro-backup-copy.timer`:

```ini
[Unit]
Description=Copy Pindoro dumps daily after the nightly dump

[Timer]
OnCalendar=*-*-* 04:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
```

```sh
sudo systemctl daemon-reload && sudo systemctl enable --now pindoro-backup-copy.timer
```

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
`data/cities/*/identity.json` (in git) need backing up.

## 8. Updating

```sh
just deploy                      # pulls, rebuilds the api image, recreates changed services
dc logs -f api caddy cloudflared
```
