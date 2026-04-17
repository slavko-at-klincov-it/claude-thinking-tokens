# Verification: Statusline Values End-to-End

All statusline values verified against raw source data via manual calculation.

## Data Pipeline: Where the Numbers Come From

The values displayed in the statusline travel through a 4-stage pipeline. No values are invented by our script, everything traces back to the Anthropic Messages API.

### Stage 1: Anthropic Messages API

When Claude Code sends a prompt to the API, the response contains a `usage` object:

```
POST https://api.anthropic.com/v1/messages
→ Response includes:
  usage.input_tokens              (fresh input tokens for this call)
  usage.output_tokens             (full output incl. thinking tokens)
  usage.cache_creation_input_tokens (tokens written to prompt cache)
  usage.cache_read_input_tokens   (tokens read from prompt cache)
```

These are **Anthropic's numbers**, not ours. We do not calculate token counts.

### Stage 2: Claude Code CLI (aggregation)

Claude Code CLI receives the API response, aggregates data, and builds the statusline JSON. Some fields are directly from the API, others are computed by Claude Code internally. We cannot inspect Claude Code's source (minified), so the exact origin of some fields is documented as "not verified."

| Field | What we know | What we don't know |
|-------|-------------|-------------------|
| `rate_limits.*.used_percentage` | Percentage of plan quota used | Exact source (not in API response body or transcript, likely from API response headers or a separate endpoint) |
| `rate_limits.*.resets_at` | Unix timestamp when the window resets | Same as above |
| `context_window.used_percentage` | Percentage of context window used | Exact formula (our reverse-engineering yielded 23% from current_usage totals, but Claude Code shows 24%, suggesting a different calculation) |
| `context_window.total_input_tokens` | Cumulative session input metric | Exact aggregation method (value 384k is too large for "sum of fresh input_tokens" (~300) but too small for "sum of all tokens sent" (millions)) |
| `context_window.total_output_tokens` | Cumulative session output metric | Same uncertainty as total_input |
| `context_window.current_usage.*` | Per-call token counts | Verified: matches API `usage` object structure and values from transcript |
| `transcript_path` | JSONL conversation log path | N/A, straightforward |

**Important**: Our script uses these values as-is for display. For `session` (line 2), we sum `total_input_tokens + total_output_tokens`. We trust that Claude Code calculates these correctly, but we cannot independently verify their exact semantics because Claude Code's aggregation logic is not documented or open-source.

### Stage 3: Statusline JSON (stdin to our script)

Claude Code pipes a JSON object to the statusline script via stdin on every UI update. This is the same JSON we log to `/tmp/claude-statusline-debug.json` for debugging. The script does not call any API, it only reads what Claude Code provides.

### Stage 4: Our Script (calculation + display)

Our script (`statusline.sh`) performs these calculations on the JSON:

| Displayed Value | Calculation | Inputs |
|-----------------|-------------|--------|
| 5h/7d % | `floor(used_percentage)` | Direct from JSON, floored for bash compatibility |
| 5h countdown | `resets_at - now()`, formatted as `Xh Ym` | resets_at from JSON, current time from `date +%s` |
| 7d reset date | `date -r resets_at "+%a %H:%M"` | resets_at from JSON, formatted by system `date` |
| ctx % | `floor(used_percentage)` | Direct from JSON |
| last API-Call | `input_tokens + cache_creation + output_tokens` | 3 fields from current_usage, **excludes** cache_read |
| session | `total_input_tokens + total_output_tokens` | 2 fields from context_window |
| cached history | `cache_read_input_tokens` | Direct from current_usage |
| thinking ON/OFF | Presence of `"type": "thinking"` content block | Parsed from JSONL transcript file |
| thinking tokens | `output_tokens - ceil(visible_chars / 2.7)` | output_tokens from transcript usage + text/tool_use char count |
| thinking intensity | `output_tokens / visible_tokens` ratio | Derived from above |

### What We Calculate vs What We Pass Through

| Category | Our role | Verified? |
|----------|----------|-----------|
| Rate limits (%, reset time) | **Pass through** from JSON, only format for display | Source of raw data not verified (Claude Code internal) |
| Context window % | **Pass through** from JSON | Source formula not verified (1% discrepancy found) |
| last API-Call | **Sum** 3 fields from `current_usage` (simple addition) | Verified: math is correct, fields come from API usage object |
| session | **Sum** 2 fields from `context_window` (simple addition) | Math verified, but exact semantics of `total_input/output_tokens` not verified |
| cached history | **Pass through** `cache_read_input_tokens` | Verified: direct from API usage object |
| thinking ON/OFF | **Parse** transcript JSONL (check content_types) | Verified: 100% reliable, tested across 12 experiments |
| thinking tokens | **Calculate** via calibrated subtraction (our formula) |
| Bar fill / colors | **Calculate** from percentage (cosmetic) |

Only the thinking token estimate uses our own formula. Everything else is either passed through directly or a trivial sum of API-provided values.

## Verification Method

1. Read raw JSON from `/tmp/claude-statusline-debug.json` (written by statusline on each invocation)
2. Extract each source field with `jq`
3. Manually calculate expected statusline output
4. Run statusline, strip ANSI codes, compare Soll vs Ist
5. Automated test suite: 55 tests covering helpers, synthetic inputs, real data, edge cases

## Live Verification (April 2026)

Source data:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 14.000000000000002, "resets_at": 1776474000 },
    "seven_day": { "used_percentage": 3, "resets_at": 1776988800 }
  },
  "context_window": {
    "used_percentage": 23,
    "total_input_tokens": 384536,
    "total_output_tokens": 181235,
    "current_usage": {
      "input_tokens": 10,
      "output_tokens": 22,
      "cache_creation_input_tokens": 423,
      "cache_read_input_tokens": 224713
    }
  }
}
```

### Results

| Value | Source Field | Calculation | Expected | Statusline | Pass |
|-------|-------------|-------------|----------|------------|------|
| 5h % | 14.000000000000002 | floor(14.0...02) | 14% | 14% | Yes |
| 5h countdown | resets_at - now = 6185s | 6185/3600=1h, (6185%3600)/60=43m | 1h43m | 1h43m | Yes |
| 5h bar fill | 14% of 10 chars | (14*10)/100 = 1 | 1 filled, 9 empty | 1 filled, 9 empty | Yes |
| 5h color | 14% <= 40 | green (ANSI 32m) | green | green | Yes |
| 7d % | 3 | floor(3) | 3% | 3% | Yes |
| 7d reset | 1776988800 | date -r 1776988800 | Fr. 02:00 | Fr. 02:00 | Yes |
| 7d bar fill | 3% of 10 chars | (3*10)/100 = 0 | 0 filled, 10 empty | 0 filled, 10 empty | Yes |
| 7d color | 3% <= 40 | green (ANSI 32m) | green | green | Yes |
| ctx | 23 | floor(23) | 23% | 23% | Yes |
| last API-Call | in=10, cc=423, out=22 | 10+423+22 = 455 | 455 | 455 | Yes |
| session | ti=384536, to=181235 | 384536+181235 = 565771 | 565.7k | 565.7k | Yes |
| cached history | cr=224713 | 224713 | 224.7k | 224.7k | Yes |
| consistency | last+cached vs total | 455+224713 = 225168 | 10+423+22+224713 = 225168 | diff = 0 | Yes |

**13/13 Pass.**

### Token Formatting Verification

The `fmt_tokens()` function formats raw numbers:

| Input | Calculation | Expected | Verified |
|-------|-------------|----------|----------|
| 455 | < 1000, show raw | 455 | Yes |
| 565771 | 565771/1000=565, (565771%1000)/100=7 | 565.7k | Yes |
| 224713 | 224713/1000=224, (224713%1000)/100=7 | 224.7k | Yes |

### Float Percentage Handling

The API sometimes returns floats like `14.000000000000002` due to floating-point precision. The statusline applies `| floor` in jq to truncate:

| API Value | After floor | Displayed |
|-----------|-------------|-----------|
| 14.000000000000002 | 14 | 14% |
| 28.000000000000004 | 28 | 28% |
| 99.9 | 99 | 99% |
| 3 | 3 | 3% |

## Automated Test Suite

Run `./test.sh` for 55 automated tests:

```
--- TEST 1: fmt_tokens() ---              8/8 PASS
--- TEST 2: build_bar() colors ---       14/14 PASS
--- TEST 3: Synthetic JSON - Line 1 ---   5/5 PASS
--- TEST 4: Synthetic JSON - Line 2 ---   4/4 PASS
--- TEST 5: Thinking with transcripts --- 4/4 PASS
--- TEST 5e: Calibration validation ---   6/6 PASS
--- TEST 6: Edge Cases ---                8/8 PASS
--- TEST 7: Real live data ---            6/6 PASS
                                        -----------
                                        55/55 PASS
```

### Edge Cases Tested

| Scenario | Input | Expected | Verified |
|----------|-------|----------|----------|
| Empty JSON | `{}` | 5h --%, 7d --%, ctx --%, no line 2 | Yes |
| Missing rate_limits | no rate_limits key | --% for both | Yes |
| Float percentage | 28.000000000000004 | 28% | Yes |
| Percentage > 100 | 150 | 150%, bar clamped to 10 filled | Yes |
| Reset in past | resets_at < now | "now" | Yes |
| Zero tokens | all 0 | 0 displayed | Yes |

## Consistency Invariant

For any statusline invocation, this invariant holds:

```
last_api_call + cached_history
  = input_tokens + cache_creation_input_tokens + output_tokens + cache_read_input_tokens
  = total current_usage
```

Verified with diff = 0 in every test.
