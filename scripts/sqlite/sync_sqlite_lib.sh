#!/bin/bash
set -e

# Check defined Github token
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Environment variable GITHUB_TOKEN is not defined."
  exit 1
fi

REPO="dailysoftwaresystems/DBAS.SQLite"
BASE_URL="https://api.github.com/repos/$REPO/contents/dbas/dist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_LIBS_DIR="$SCRIPT_DIR/../../native_libs"
OUT_DIR="$NATIVE_LIBS_DIR/sqlite"

download_recursive() {
    local url=$1
    local path=$2

    echo "Reading: $url into $path"

    curl -s "$url" -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw" | jq -c '.[]' | while read -r item; do
        type=$(echo "$item" | jq -r '.type')
        name=$(echo "$item" | jq -r '.name')
        download_url=$(echo "$item" | jq -r '.download_url')
        next_url=$(echo "$item" | jq -r '.url')
        target_path="$path/$name"

        if [ "$type" = "file" ]; then
            echo "Downloading $target_path"
            mkdir -p "$path"
            curl -sL "$download_url" -o "$target_path" -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw"
        elif [ "$type" = "dir" ]; then
            download_recursive "$next_url" $target_path
        fi
    done
}

rm -rf "$NATIVE_LIBS_DIR/sqlite/*"
mkdir -p "$OUT_DIR"
download_recursive "$BASE_URL" "$OUT_DIR"

echo "All binaries downloaded in: $OUT_DIR, copying binaries to respective platform directories..."

echo "Copying android binaries..."
mkdir -p "$SCRIPT_DIR/../../android/src/main/jniLibs/arm64-v8a"
mkdir -p "$SCRIPT_DIR/../../android/src/main/jniLibs/armeabi-v7a"
mkdir -p "$SCRIPT_DIR/../../android/src/main/jniLibs/x86_64"
mkdir -p "$SCRIPT_DIR/../../windows/libs"
mkdir -p "$SCRIPT_DIR/../../linux/libs"
mkdir -p "$SCRIPT_DIR/../../web/libs"
mkdir -p "$SCRIPT_DIR/../../example/web/libs"

cp -r "$OUT_DIR/android/a64/"* "$SCRIPT_DIR/../../android/src/main/jniLibs/arm64-v8a"
cp -r "$OUT_DIR/android/armeabi/"* "$SCRIPT_DIR/../../android/src/main/jniLibs/armeabi-v7a"
cp -r "$OUT_DIR/android/x86_64/"* "$SCRIPT_DIR/../../android/src/main/jniLibs/x86_64"
cp -r "$OUT_DIR/windows/*"* "$SCRIPT_DIR/../../windows/libs"
cp -r "$OUT_DIR/linux/*"* "$SCRIPT_DIR/../../linux/libs"
cp -r "$OUT_DIR/web/*"* "$SCRIPT_DIR/../../web/libs"
cp -r "$OUT_DIR/web/*"* "$SCRIPT_DIR/../../example/web/libs"

echo "Copying ios binaries..."
mkdir -p "$SCRIPT_DIR/../../ios/dbas_sqlite.xcframework"
cp -r "$OUT_DIR/ios/dbas_sqlite.xcframework/"* "$SCRIPT_DIR/../../ios/dbas_sqlite.xcframework"

echo "Copying macos binaries..."
mkdir -p "$SCRIPT_DIR/../../macos/dbas_sqlite.xcframework"
cp -r "$OUT_DIR/macos/dbas_sqlite.xcframework/"* "$SCRIPT_DIR/../../macos/dbas_sqlite.xcframework"

echo "All platform binaries copied successfully."