# Single entry point for every Pindoro command.

# Recipes are sh; on Windows use Git for Windows' sh (`bash` on PATH may be WSL's).
set windows-shell := ["C:/Program Files/Git/bin/sh.exe", "-cu"]

dc := "docker compose -f infra/docker-compose.yml"
dc_prod := "docker compose --env-file .env -f infra/docker-compose.prod.yml"
melos := "dart run melos"
# Flutter that renders goldens; keep equal to flutter-version in .github/workflows/mobile.yml.
flutter_version := "3.47.9"
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

# Native app icon and splash from the branding assets (design-system asset groups)
branding:
    cd packages/pindoro_design && flutter test tool/rasterize_branding_test.dart
    cd apps/mobile && dart pub global run flutter_launcher_icons -f flutter_launcher_icons.yaml
    cp apps/mobile/assets/branding/png/splash-mark.png apps/mobile/android/app/src/main/res/drawable-xxxhdpi/splash.png
    cp apps/mobile/assets/branding/png/splash-mark-dark.png apps/mobile/android/app/src/main/res/drawable-night-xxxhdpi/splash.png

# Fail when generated tokens are stale
tokens-check:
    dart run packages/pindoro_design/tool/generate_tokens.dart
    git diff --exit-code -- packages/pindoro_design/lib/src/generated

# Regenerate pindoro_design goldens on Linux, the only platform that compares them
goldens:
    MSYS_NO_PATHCONV=1 docker run --rm \
      -v "{{ justfile_directory() }}:/repo" -v /repo/.dart_tool -v /repo/packages/pindoro_design/.dart_tool \
      -v pindoro-flutter-{{ flutter_version }}:/flutter -w /repo/packages/pindoro_design \
      ghcr.io/cirruslabs/flutter:3.44.0 sh -c '[ -x /flutter/bin/flutter ] || git clone -q --depth 1 -b {{ flutter_version }} https://github.com/flutter/flutter.git /flutter; /flutter/bin/flutter pub get && /flutter/bin/flutter test --update-goldens test/widgets_test.dart test/components_test.dart'

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
