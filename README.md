# Tokage

Tokage is a lightweight macOS menu‑bar utility that tallies your Codex JSONL session logs and surfaces daily token usage, near‑term history, and calendar‑month totals.

## Features

- **Menu‑bar first**: Runs headless with a Menu Bar Extra on macOS 13+, showing today’s usage, quick refresh, and a Quit action.  
- **Daily focus**: Reads Codex JSONL session logs and attributes token events by their ISO timestamps; folders are only discovery hints.  
- **Historical rollup**: Caches the previous six days (yesterday + five more) and a calendar-month summary, refreshing only the missing days to reduce disk churn.  
- **Model-aware pricing**: Reads `turn_context` model ids and applies bundled GPT-5 family pricing, including GPT-5.6 Sol, Terra, and Luna, with a generic fallback for unknown models.  
- **Cost breakdown**: Estimates API-equivalent billable input, cached input, and output costs; reasoning tokens are already included in output and are not billed twice.  
- **Long-context pricing**: Applies published per-request input and output multipliers when a supported model exceeds 272,000 input tokens.  
- **Safe fallback**: Recently modified older rollout files are scanned and cached, so long-running Codex goals/tasks count on the day their token events happened without a full root scan on every refresh.

## Usage

1. Build/run in Xcode 15+ (macOS 13.0 target).  
2. Ensure Codex logs are available under `~/.codex/sessions`.  
3. Launch the app; a menu-bar icon appears showing totals.  
4. Click the menu for today’s breakdown, “Recent” history, and “This Month”.  
5. Use “Refresh Now” to force a recount; “Quit Tokage” exits cleanly.

## Implementation Notes

- Daily aggregation uses incremental `FileState` offsets; we only parse new lines per file.  
- File discovery checks target folders every refresh, keeps cached active older files, and throttles full `~/.codex/sessions` sweeps to reduce repeated filesystem work.  
- Historical cache keys are ISO day strings; month cache keys are `YYYY-MM`.  
- When totals change for today we adjust the cached month by computing the delta.  
- ISO timestamps are the source of truth for day/month attribution because long-running Codex goals can append later events to older rollout files.

## Matching ccusage

The logic mirrors ccusage’s token normalization (`cache_read_input_tokens` fallback, reasoning included in output, etc.). Dollar values are API-equivalent estimates rather than Codex subscription invoices. GPT-5.6 cache-write premiums are not included because Codex session logs do not expose cache-write token counts.  
If you need cross-verification, run ccusage against the same log tree—the totals should align within rounding.

## Release (Sparkle + DMG)

1. Set versions in Xcode: `MARKETING_VERSION` (e.g., `1.0`) and `CURRENT_PROJECT_VERSION` (build number).  
2. Ensure Sparkle keys are set in build settings (`SUFeedURL`, `SUPublicEDKey`).  
3. Archive and export with **Developer ID** signing (Xcode → Product → Archive → Distribute App → Developer ID).  
4. Create the DMG, notarize/staple it, and sign it for Sparkle:
   ```bash
   scripts/release-dmg.sh
   ```
   Defaults: `~/Downloads/Tokage.app`, Sparkle in `~/Downloads/Sparkle` or `~/Downloads/Sparkle-for-Swift-Package-Manager`, Sparkle Keychain account `ed25519`, and notary profile `AC_PROFILE`. Use `scripts/release-dmg.sh --help` for overrides.

Manual equivalent for steps 4-6:

4. Create a DMG:
   ```bash
   scripts/create-dmg.sh /path/to/Exported/Tokage.app
   scripts/create-dmg.sh ~/Downloads/Tokage/Tokage.app
   ```
5. Notarize and staple the DMG:
   ```bash
   xcrun notarytool submit dist/Tokage.dmg --keychain-profile "AC_PROFILE" --wait
   xcrun stapler staple dist/Tokage.dmg
   ```
6. Sign the DMG for Sparkle (from the Sparkle release bundle):
   ```bash
   /path/to/Sparkle/bin/sign_update --ed-key-file /path/to/private_key.pem dist/Tokage.dmg
   /path/to/Sparkle/bin/sign_update --ed-key-file /path/to/private_key.pem dist/Tokage.dmg
   ```
7. Update `appcast.xml` with `sparkle:version`, `sparkle:shortVersionString`, `sparkle:edSignature`, and `length`, then upload the DMG + appcast to `SUFeedURL`.
