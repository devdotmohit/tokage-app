#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
OUT_DIR="${2:-dist}"
VOL_NAME="${3:-Tokage}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/Tokage.app [out-dir] [volume-name]" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

if [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$ROOT_DIR/$OUT_DIR"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STAGING_DIR="$TMP_DIR/$VOL_NAME"
APP_NAME="$(basename "$APP_PATH")"

mkdir -p "$STAGING_DIR"
mkdir -p "$OUT_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$OUT_DIR/$VOL_NAME.dmg"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Created DMG: $DMG_PATH"
