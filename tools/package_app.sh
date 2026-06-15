#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Release}"
APP_NAME="luma.app"
DIST_DIR="$ROOT_DIR/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZIP_PATH="$DIST_DIR/luma-$STAMP.zip"

cd "$ROOT_DIR"

xcodebuild -project OfficeWorkoutCoach.xcodeproj \
  -scheme OfficeWorkoutCoach \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  build

BUILD_DIR="$(xcodebuild -project OfficeWorkoutCoach.xcodeproj \
  -scheme OfficeWorkoutCoach \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/TARGET_BUILD_DIR =/ { print $2; exit }')"

SOURCE_APP="$BUILD_DIR/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found: $SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
ditto -c -k --keepParent "$SOURCE_APP" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Packaged: $ZIP_PATH"
echo "Checksum: $ZIP_PATH.sha256"
