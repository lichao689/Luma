#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Release}"
APP_NAME="luma.app"
VOL_NAME="luma"
DIST_DIR="$ROOT_DIR/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
DMG_PATH="$DIST_DIR/luma-$STAMP.dmg"

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
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/luma-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

ditto "$SOURCE_APP" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Packaged: $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
