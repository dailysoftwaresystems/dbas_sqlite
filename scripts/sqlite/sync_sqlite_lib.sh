#!/bin/bash
set -e

# Check defined Github token
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Environment variable GITHUB_TOKEN is not defined."
  exit 1
fi

REPO="dailysoftwaresystems/DBAS.SQLite"
BRANCH="main"
BASE_URL="https://api.github.com/repos/$REPO/contents/dbas/dist"

# Files by platform
declare -A FILES
FILES[android]="dbas_sqlite.so"
FILES[ios]="dbas_sqlite.dylib"
FILES[macos]="dbas_sqlite.dylib"
FILES[linux]="dbas_sqlite.so"
FILES[windows]="dbas_sqlite.dll"
FILES[web]="dbas_sqlite.wasm dbas_sqlite.js"

# Output directory
OUT_DIR="../../dbas_base_app/native_libs/sqlite"
mkdir -p "$OUT_DIR"

echo "Downloading binaries from $REPO (branch: $BRANCH)..."

for platform in "${!FILES[@]}"; do
    mkdir -p "$OUT_DIR/$platform"
    for file in ${FILES[$platform]}; do
        url="$BASE_URL/$platform/$file?ref=$BRANCH"
        dest="$OUT_DIR/$platform/$file"
        echo "-> Downloading $url"
        curl -sSfL \
          -H "Authorization: token $GITHUB_TOKEN" \
          -H "Accept: application/vnd.github.v3.raw" \
          "$url" -o "$dest"
    done
done

echo "All binaries downloaded in: $OUT_DIR"

# TODO: Must copy android one to: android\src\main\jniLibs\<all sub directories>