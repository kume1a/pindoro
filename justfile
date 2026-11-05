# Single entry point for every Pindoro command. On Windows run `just` from Git Bash.

dc := "docker compose -f infra/docker-compose.yml"
dc_prod := "docker compose --env-file .env -f infra/docker-compose.prod.yml"
melos := "dart run melos"
# Relative to the pipeline container workdir (/repo/pipeline); absolute paths get mangled by Git Bash.
fixture_pack := "../apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite"

default:
    @just --list

# Install pnpm and Dart workspace dependencies
setup:
    pnpm install
    {{ melos }} bootstrap

# Generate code: design tokens and Drift
gen:
    dart run packages/pindoro_design/tool/generate_tokens.dart
    cd apps/mobile && dart run build_runner build

# Fail when generated tokens are stale
tokens-check:
    dart run packages/pindoro_design/tool/generate_tokens.dart
    git diff --exit-code -- packages/pindoro_design/lib/src/generated

# Regenerate pindoro_design goldens on Linux, the only platform that compares them
goldens:
    MSYS_NO_PATHCONV=1 docker run --rm -v "{{ justfile_directory() }}:/repo" -v /repo/.dart_tool -v /repo/packages/pindoro_design/.dart_tool -w /repo/packages/pindoro_design ghcr.io/cirruslabs/flutter:stable sh -c "flutter pub get && flutter test --update-goldens test/widgets_test.dart"

# Biome, tsc, dart format, flutter analyze
lint:
    pnpm exec biome check .
    pnpm -r typecheck
    dart format --set-exit-if-changed .
    {{ melos }} run analyze

# Every test suite (pipeline DB tests run inside the pipeline image, which has osm2pgsql)
test:
    {{ melos }} run test
    {{ dc }} up -d --wait postgis
    pnpm --filter @pindoro/geo test
    pnpm --filter @pindoro/api test
    {{ dc }} run --rm --build -e PINDORO_REQUIRE_OSM_TOOLS=1 -e TEST_DATABASE_URL=postgres://pindoro:pindoro@postgis:5432/pindoro_pipeline_test --entrypoint pnpm pipeline test

# Dev stack: PostGIS, API (tsx watch), Martin tiles, packs file server
dev:
    {{ dc }} up --build postgis api martin packs

# Build the Vake fixture pack bundled with the app
fixture:
    {{ dc }} run --rm --build pipeline fetch tbilisi
    {{ dc }} run --rm pipeline build tbilisi --fixture
    {{ dc }} run --rm pipeline validate {{ fixture_pack }}

# Build, validate and publish a full city pack into PACKS_DIR
pack CITY:
    {{ dc }} run --rm --build pipeline fetch {{ CITY }}
    {{ dc }} run --rm pipeline build {{ CITY }}
    {{ dc }} run --rm pipeline validate {{ CITY }}
    {{ dc }} run --rm pipeline publish {{ CITY }}

# Download the Georgia vector tiles and regenerate the app map styles
tiles:
    {{ dc }} run --rm --build pipeline tiles

# Write shared/openapi/openapi.json from the API routes
openapi:
    pnpm --filter @pindoro/api openapi

# Run the app (pass e.g. `-d emulator-5554` or `--dart-define=TILES_BASE_URL=...`)
run-mobile *ARGS:
    cd apps/mobile && flutter run {{ ARGS }}

# On the server: pull and (re)start the production stack
deploy:
    git pull --ff-only
    {{ dc_prod }} up -d --build
