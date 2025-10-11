# Tokage Agents Overview

This document summarizes the operational choices implemented in the Tokage menu‑bar app so future agents (or your future self) understand the current behavior quickly.

## File Discovery

- Primary source: `~/.codex/sessions/YYYY/MM/DD` directory for the target day.  
- Secondary: month directory (`~/.codex/sessions/YYYY/MM`) picking files whose path contains the day component.  
- Fallback: entire month tree, or last resort the sessions root; events from these fallbacks are filtered by timestamp to stay day-correct.

## Token Parsing

- Decode each JSONL line, expect `type == "event_msg"` and payload `type == "token_count"`.  
- Normalize totals:  
  - Use `cached_input_tokens` with a fallback to `cache_read_input_tokens`.  
  - Input minus cached gives billable input; total falls back to input + output when missing.  
  - Reasoning tokens are clamped not to exceed output tokens.  
- Deltas: prefer `last_token_usage`; otherwise subtract cumulative totals from previous event (with negative guard).

## Deduplication

- Per file dedupe via `FileState.lastSignature` only; we no longer skip events across files (avoids undercounting).  
- Month aggregation uses its own signature set per scan.

## Historical Cache

- Yesterday + five prior days stored by day key.  
- Refresh only fetches missing days; cached days persist until a new day triggers a cache reset.  
- Month summaries stored by `YYYY-MM`, adjusted in place when today’s totals change.

## UI / UX

- Menu-bar summary mirrors ccusage formatting, with K/M/B abbreviations using two decimals.  
- “Recent” reports yesterday and five formatted dates (ordinal day + month name).  
- “This Month (…)” shows the month label and cumulative totals.  
- Refresh button fires the same background pipeline; Quit exits the accessory app (dockless).

## Gotchas

- When a day folder exists we trust it and skip timestamp gating; logs mis-timestamped but placed in the folder still count.  
- If only month-level files exist we fall back to timestamp filtering to keep days accurate.  
- Monthly totals can be heavy if the tree is large; consider batching or streaming if performance regresses.
