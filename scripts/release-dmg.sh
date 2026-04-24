#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

APP_PATH="${TOKAGE_APP_PATH:-$HOME/Downloads/Tokage.app}"
SPARKLE_DIR="${SPARKLE_DIR:-}"
ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PROFILE}"
OUT_DIR="${OUT_DIR:-dist}"
VOL_NAME="${VOL_NAME:-Tokage}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Runs release steps 4-6:
  4. Create DMG
  5. Notarize and staple DMG
  6. Sign DMG for Sparkle

Options:
  --app PATH             Exported app bundle. Default: ~/Downloads/Tokage.app
  --sparkle-dir PATH     Sparkle release folder. Default: auto-detect in ~/Downloads
  --ed-key-file PATH     Optional Sparkle EdDSA private key file. Default: use Keychain
  --keychain-account ID  Sparkle Keychain account. Default: ed25519
  --notary-profile NAME  notarytool keychain profile. Default: AC_PROFILE
  --out-dir PATH         Output directory. Default: dist
  --volume-name NAME     DMG volume/name. Default: Tokage
  -h, --help             Show this help

Environment overrides:
  TOKAGE_APP_PATH, SPARKLE_DIR, SPARKLE_ED_KEY_FILE, SPARKLE_KEYCHAIN_ACCOUNT,
  NOTARY_PROFILE, OUT_DIR, VOL_NAME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --sparkle-dir)
      SPARKLE_DIR="${2:-}"
      shift 2
      ;;
    --ed-key-file)
      ED_KEY_FILE="${2:-}"
      shift 2
      ;;
    --keychain-account)
      KEYCHAIN_ACCOUNT="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --volume-name)
      VOL_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SPARKLE_DIR" ]]; then
  if [[ -d "$HOME/Downloads/Sparkle" ]]; then
    SPARKLE_DIR="$HOME/Downloads/Sparkle"
  elif [[ -d "$HOME/Downloads/Sparkle-for-Swift-Package-Manager" ]]; then
    SPARKLE_DIR="$HOME/Downloads/Sparkle-for-Swift-Package-Manager"
  else
    SPARKLE_DIR="$HOME/Downloads/Sparkle"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -d "$SPARKLE_DIR" ]]; then
  echo "Sparkle folder not found: $SPARKLE_DIR" >&2
  exit 1
fi

SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update not found or not executable: $SIGN_UPDATE" >&2
  exit 1
fi

if [[ -n "$ED_KEY_FILE" && ! -f "$ED_KEY_FILE" ]]; then
  echo "Sparkle EdDSA private key not found: $ED_KEY_FILE" >&2
  exit 1
fi

if [[ -z "$KEYCHAIN_ACCOUNT" ]]; then
  echo "Sparkle Keychain account cannot be empty" >&2
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Notary profile cannot be empty" >&2
  exit 1
fi

if [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$ROOT_DIR/$OUT_DIR"
fi

DMG_PATH="$OUT_DIR/$VOL_NAME.dmg"

echo "Creating DMG from: $APP_PATH"
"$SCRIPT_DIR/create-dmg.sh" "$APP_PATH" "$OUT_DIR" "$VOL_NAME"

echo "Submitting for notarization with profile: $NOTARY_PROFILE"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "Signing DMG for Sparkle"
if [[ -n "$ED_KEY_FILE" ]]; then
  "$SIGN_UPDATE" --ed-key-file "$ED_KEY_FILE" "$DMG_PATH"
else
  "$SIGN_UPDATE" --account "$KEYCHAIN_ACCOUNT" "$DMG_PATH"
fi

echo
echo "DMG: $DMG_PATH"
echo "Length: $(stat -f%z "$DMG_PATH")"
