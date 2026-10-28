#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Release}"
DEST_DIR="${DEST_DIR:-$HOME/Applications}"
APP_NAME="luma.app"
# 额外的 xcodebuild 参数,默认空。用于在受限环境里补开关,例如:
#   EXTRA_XCODEBUILD_ARGS='OTHER_SWIFT_FLAGS="-disable-sandbox"' tools/install_app.sh
EXTRA_XCODEBUILD_ARGS="${EXTRA_XCODEBUILD_ARGS:-}"

cd "$ROOT_DIR"

xcodebuild -project OfficeWorkoutCoach.xcodeproj \
  -scheme OfficeWorkoutCoach \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  ${EXTRA_XCODEBUILD_ARGS} \
  build

BUILD_DIR="$(xcodebuild -project OfficeWorkoutCoach.xcodeproj \
  -scheme OfficeWorkoutCoach \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/TARGET_BUILD_DIR =/ { print $2; exit }')"

SOURCE_APP="$BUILD_DIR/$APP_NAME"
DEST_APP="$DEST_DIR/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found: $SOURCE_APP" >&2
  exit 1
fi

pkill -x OfficeWorkoutCoach 2>/dev/null || true
pkill -x luma 2>/dev/null || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/OfficeWorkoutCoach.app"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"
if ! open -n "$DEST_APP"; then
  echo "Installed, but macOS did not open the app automatically: $DEST_APP" >&2
  exit 0
fi

echo "Installed and opened: $DEST_APP"
