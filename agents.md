# Tokage Agents Overview

This document summarizes the operational choices implemented in the Tokage menu‑bar app so future agents (or your future self) understand the current behavior quickly.

## File Discovery

- Primary discovery: `~/.codex/sessions/YYYY/MM/DD` directory for the target day.  
- Secondary discovery: the target month directory and cached recently modified session files under the sessions root.  
- Full sessions-root sweeps are throttled; target day/month folders are still checked every refresh.  
- Attribution source of truth: event ISO timestamps, not folder paths. Long-running Codex goals can append later events to older rollout files.

## Token Parsing

- Decode each JSONL line, expect `type == "event_msg"` and payload `type == "token_count"`.  
- Normalize totals:  
  - Use `cached_input_tokens` with a fallback to `cache_read_input_tokens`.  
  - Input minus cached gives billable input; total falls back to input + output when missing.  
  - Reasoning tokens are clamped not to exceed output tokens.  
- Deltas: prefer `last_token_usage`; otherwise subtract cumulative totals from previous event (with negative guard).

## Pricing

- Resolve each `turn_context` model through the bundled catalog; unknown models use the generic fallback.  
- Reasoning is a subset of output, so output tokens and costs are counted once.  
- Supported GPT-5.4+ models apply 2x input/cached-input and 1.5x output rates when a single usage event exceeds 272,000 input tokens.  
- Dollar values are standard API-equivalent estimates. Astra and GPT-5.6 cache-write premiums are included when `cache_write_input_tokens` is present (zero for older logs). Cache writes are a subset of uncached input, counted and charged once.
- Rates in `Tokage/ModelPricing.json` were verified September 6, 2026; GPT-5.6 Sol promotional pricing should be rechecked when it changes (available at least through November 21, 2026).

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

- Folder dates are discovery hints only; all counted token events must match the requested day/month by timestamp.  
- Recently modified older session files are cached so active long-running goals are not missed between throttled root sweeps.  
- Monthly totals can be heavy if the tree is large; consider batching or streaming if performance regresses.
