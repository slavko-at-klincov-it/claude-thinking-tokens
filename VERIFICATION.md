# Verification: Statusline Values End-to-End

All statusline values verified against raw source data via manual calculation.

## Method

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
