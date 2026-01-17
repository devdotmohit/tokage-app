# Tokage

Tokage is a lightweight macOS menu‑bar utility that tallies your Codex JSONL session logs and surfaces daily token usage, near‑term history, and calendar‑month totals.

## Features

- **Menu‑bar first**: Runs headless with a Menu Bar Extra on macOS 13+, showing today’s usage, quick refresh, and a Quit action.  
- **Daily focus**: Reads JSONL session logs under `~/.codex/sessions/YYYY/MM/DD` and counts any token events found there without re-checking timestamps (trusts local folder structure).  
- **Historical rollup**: Caches the previous six days (yesterday + five more) and a calendar-month summary, refreshing only the missing days to reduce disk churn.  
- **Cost breakdown**: Mirrors ccusage logic for billable vs cached input, output, and reasoning tokens; reasoning is billed at the output rate.  
- **Safe fallback**: If a day folder is empty we fall back to month-level logs while filtering by timestamp, so misfiled entries still count correctly.

## Usage

1. Build/run in Xcode 15+ (macOS 13.0 target).  
2. Ensure Codex logs are available under `~/.codex/sessions`.  
3. Launch the app; a menu-bar icon appears showing totals.  
4. Click the menu for today’s breakdown, “Recent” history, and “This Month”.  
5. Use “Refresh Now” to force a recount; “Quit Tokage” exits cleanly.

## Implementation Notes

- Daily aggregation uses incremental `FileState` offsets; we only parse new lines per file.  
- Historical cache keys are ISO day strings; month cache keys are `YYYY-MM`.  
- When totals change for today we adjust the cached month by computing the delta.  
- ISO timestamps are still parsed to guard against misfiled entries when not in the day path.

## Matching ccusage

The logic mirrors ccusage’s token normalization (`cache_read_input_tokens` fallback, reasoning included in output, etc.).  
If you need cross-verification, run ccusage against the same log tree—the totals should align within rounding.

## Release (Sparkle + DMG)

1. Set versions in Xcode: `MARKETING_VERSION` (e.g., `1.0`) and `CURRENT_PROJECT_VERSION` (build number).  
2. Ensure Sparkle keys are set in build settings (`SUFeedURL`, `SUPublicEDKey`).  
3. Archive and export with **Developer ID** signing (Xcode → Product → Archive → Distribute App → Developer ID).  
4. Create a DMG:
   ```bash
   scripts/create-dmg.sh /path/to/Exported/Tokage.app
   ```
5. Notarize and staple the DMG:
   ```bash
   xcrun notarytool submit dist/Tokage.dmg --keychain-profile "AC_PROFILE" --wait
   xcrun stapler staple dist/Tokage.dmg
   ```
6. Sign the DMG for Sparkle (from the Sparkle release bundle):
   ```bash
   /path/to/Sparkle/bin/sign_update --ed-key-file /path/to/private_key.pem dist/Tokage.dmg
   ```
7. Update `appcast.xml` with `sparkle:version`, `sparkle:shortVersionString`, `sparkle:edSignature`, and `length`, then upload the DMG + appcast to `SUFeedURL`.
