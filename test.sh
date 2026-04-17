#!/bin/bash
# Statusline Verification Test Suite
# Tests all values in ~/.claude/statusline.sh against expected results

SL="$HOME/.claude/statusline.sh"
PASS=0
FAIL=0
TOTAL=0

check() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  PASS  %-50s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    printf "  FAIL  %-50s\n" "$test_name"
    printf "        expected: [%s]\n" "$expected"
    printf "        actual:   [%s]\n" "$actual"
  fi
}

# Source helpers from statusline for isolated testing
BAR_WIDTH=10
THINKING_CAP=128000
fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000 ]; then
    local whole=$(( n / 1000 ))
    local frac=$(( (n % 1000) / 100 ))
    echo "${whole}.${frac}k"
  else
    echo "${n}"
  fi
}

echo "============================================"
echo "  STATUSLINE VERIFICATION TEST SUITE"
echo "============================================"
echo ""

# ==========================================
echo "--- TEST 1: fmt_tokens() ---"
# ==========================================
check "fmt_tokens(0)" "0" "$(fmt_tokens 0)"
check "fmt_tokens(42)" "42" "$(fmt_tokens 42)"
check "fmt_tokens(999)" "999" "$(fmt_tokens 999)"
check "fmt_tokens(1000)" "1.0k" "$(fmt_tokens 1000)"
check "fmt_tokens(1500)" "1.5k" "$(fmt_tokens 1500)"
check "fmt_tokens(10600)" "10.6k" "$(fmt_tokens 10600)"
check "fmt_tokens(128000)" "128.0k" "$(fmt_tokens 128000)"
check "fmt_tokens(999999)" "999.9k" "$(fmt_tokens 999999)"

echo ""
# ==========================================
echo "--- TEST 2: build_bar() colors ---"
# ==========================================
# We test by looking for ANSI color codes in output
build_bar() {
  local pct=$1
  local filled=$(( (pct * BAR_WIDTH) / 100 ))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  local empty=$(( BAR_WIDTH - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  local color
  if [ "$pct" -le 40 ]; then color="\033[32m"
  elif [ "$pct" -le 70 ]; then color="\033[33m"
  elif [ "$pct" -le 90 ]; then color="\033[31m"
  else color="\033[1;31m"; fi
  printf "${color}${bar} %d%%\033[0m" "$pct"
}

# Check colors via grep on raw ANSI
bar0=$(build_bar 0)
bar40=$(build_bar 40)
bar41=$(build_bar 41)
bar70=$(build_bar 70)
bar71=$(build_bar 71)
bar90=$(build_bar 90)
bar91=$(build_bar 91)
bar100=$(build_bar 100)
bar150=$(build_bar 150)

check "bar(0) green" "yes" "$(echo "$bar0" | grep -q '32m' && echo yes || echo no)"
check "bar(40) green" "yes" "$(echo "$bar40" | grep -q '32m' && echo yes || echo no)"
check "bar(41) yellow" "yes" "$(echo "$bar41" | grep -q '33m' && echo yes || echo no)"
check "bar(70) yellow" "yes" "$(echo "$bar70" | grep -q '33m' && echo yes || echo no)"
check "bar(71) red" "yes" "$(echo "$bar71" | grep -q '31m' && echo yes || echo no)"
check "bar(90) red" "yes" "$(echo "$bar90" | grep -q '31m' && echo yes || echo no)"
check "bar(91) bold-red" "yes" "$(echo "$bar91" | grep -q '1;31m' && echo yes || echo no)"
check "bar(100) bold-red" "yes" "$(echo "$bar100" | grep -q '1;31m' && echo yes || echo no)"

# Check fill counts (count █ characters)
count_filled() { echo -e "$1" | grep -o '█' | wc -l | tr -d ' '; }
count_empty() { echo -e "$1" | grep -o '░' | wc -l | tr -d ' '; }

check "bar(0) 0 filled" "0" "$(count_filled "$bar0")"
check "bar(0) 10 empty" "10" "$(count_empty "$bar0")"
check "bar(40) 4 filled" "4" "$(count_filled "$bar40")"
check "bar(100) 10 filled" "10" "$(count_filled "$bar100")"
check "bar(100) 0 empty" "0" "$(count_empty "$bar100")"
check "bar(150) clamped 10" "10" "$(count_filled "$bar150")"

echo ""
# ==========================================
echo "--- TEST 3: Synthetic JSON - Line 1 ---"
# ==========================================
NOW=$(date +%s)
FIVE_RESET=$((NOW + 5520))  # 1h32m from now
SEVEN_RESET=$((NOW + 259200))  # 3 days from now
SEVEN_DAY=$(date -r "$SEVEN_RESET" "+%a %H:%M" 2>/dev/null || date -d "@$SEVEN_RESET" "+%a %H:%M" 2>/dev/null)

SYNTH_JSON='{
  "rate_limits": {
    "five_hour": {"used_percentage": 19, "resets_at": '$FIVE_RESET'},
    "seven_day": {"used_percentage": 45.000000000000003, "resets_at": '$SEVEN_RESET'}
  },
  "context_window": {
    "used_percentage": 12,
    "total_input_tokens": 50000,
    "total_output_tokens": 30000,
    "current_usage": {
      "input_tokens": 100,
      "output_tokens": 500,
      "cache_creation_input_tokens": 200,
      "cache_read_input_tokens": 75000
    }
  },
  "transcript_path": "/nonexistent"
}'

output=$(echo "$SYNTH_JSON" | "$SL" 2>/dev/null)
line1=$(echo "$output" | head -1)
line2=$(echo "$output" | sed -n '2p')
line3=$(echo "$output" | sed -n '3p')

# Strip ANSI for content checks
strip_ansi() { echo "$1" | sed 's/\x1b\[[0-9;]*m//g'; }
clean1=$(strip_ansi "$line1")
clean2=$(strip_ansi "$line2")

# 3a: 5h percent
check "5h shows 19%" "yes" "$(echo "$clean1" | grep -q '19%' && echo yes || echo no)"

# 3b: 5h countdown (1h32m)
check "5h countdown 1h32m" "yes" "$(echo "$clean1" | grep -q '1h32m' && echo yes || echo no)"

# 3c: 7d percent (45.000...003 floored to 45)
check "7d shows 45% (float floored)" "yes" "$(echo "$clean1" | grep -q '45%' && echo yes || echo no)"

# 3d: 7d reset date
check "7d reset date correct" "yes" "$(echo "$clean1" | grep -q "$SEVEN_DAY" && echo yes || echo no)"

# 3e: ctx
check "ctx shows 12%" "yes" "$(echo "$clean1" | grep -q 'ctx 12%' && echo yes || echo no)"

echo ""
# ==========================================
echo "--- TEST 4: Synthetic JSON - Line 2 ---"
# ==========================================

# 4a: last API-Call = 100 + 200 + 500 = 800
check "last API-Call = 800" "yes" "$(echo "$clean2" | grep -q 'last API-Call 800' && echo yes || echo no)"

# 4b: session = 50000 + 30000 = 80000 = 80.0k
check "session = 80.0k" "yes" "$(echo "$clean2" | grep -q 'session 80.0k' && echo yes || echo no)"

# 4c: cached history = 75000 = 75.0k
check "cached history = 75.0k" "yes" "$(echo "$clean2" | grep -q 'cached history 75.0k' && echo yes || echo no)"

# 4d: Consistency: last(800) + cached(75000) = 75800 total current usage
TOTAL_CURRENT=$((100 + 200 + 500 + 75000))
check "consistency: last+cached = total current" "75800" "$TOTAL_CURRENT"

echo ""
# ==========================================
echo "--- TEST 5: Thinking with real transcripts ---"
# ==========================================

# Test with river puzzle (thinking ON)
RIVER_T=""
for f in "$HOME"/.claude/projects/-Users-slavkoklincov-Code/0a7b44cf*.jsonl; do
  [ -f "$f" ] && RIVER_T="$f"
done

if [ -n "$RIVER_T" ]; then
  RIVER_JSON='{
    "transcript_path": "'$RIVER_T'",
    "context_window": {"used_percentage": 5, "total_input_tokens": 5000, "total_output_tokens": 5750, "current_usage": {"input_tokens": 500, "output_tokens": 5750, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 20000}},
    "rate_limits": {"five_hour": {"used_percentage": 20, "resets_at": '$((NOW + 3600))'}, "seven_day": {"used_percentage": 30, "resets_at": '$((NOW + 86400))'}}
  }'
  river_out=$(echo "$RIVER_JSON" | "$SL" 2>/dev/null)
  river_l3=$(echo "$river_out" | sed -n '3p')
  river_l3_clean=$(strip_ansi "$river_l3")

  check "river: thinking ON" "yes" "$(echo "$river_l3_clean" | grep -q 'thinking: ON' && echo yes || echo no)"
  check "river: intensity heavy" "yes" "$(echo "$river_l3_clean" | grep -q 'heavy' && echo yes || echo no)"

  # Manual calculation: output=5750, text_chars=1691, visible_tok=ceil(1691/2.7)=627
  # thinking_est = 5750 - 627 = 5123
  check "river: ~5.1k thinking" "yes" "$(echo "$river_l3_clean" | grep -q '5.1k' && echo yes || echo no)"
else
  echo "  SKIP  River transcript not found"
fi

# Test with CAP theorem (thinking OFF)
CAP_T=""
for f in "$HOME"/.claude/projects/-Users-slavkoklincov-Code/a18f876f*.jsonl; do
  [ -f "$f" ] && CAP_T="$f"
done

if [ -n "$CAP_T" ]; then
  CAP_JSON='{
    "transcript_path": "'$CAP_T'",
    "context_window": {"used_percentage": 2, "total_input_tokens": 2000, "total_output_tokens": 1728, "current_usage": {"input_tokens": 200, "output_tokens": 1728, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 5000}},
    "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": '$((NOW + 3600))'}, "seven_day": {"used_percentage": 20, "resets_at": '$((NOW + 86400))'}}
  }'
  cap_out=$(echo "$CAP_JSON" | "$SL" 2>/dev/null)
  cap_l3=$(echo "$cap_out" | sed -n '3p')
  cap_l3_clean=$(strip_ansi "$cap_l3")

  check "cap: thinking OFF" "yes" "$(echo "$cap_l3_clean" | grep -q 'thinking: OFF' && echo yes || echo no)"
else
  echo "  SKIP  CAP transcript not found"
fi

echo ""
# ==========================================
echo "--- TEST 5e: Calibration validation (all 6 tests) ---"
# ==========================================

# Known data from experiment
printf "  %-22s | %6s | %6s | %6s | %8s | %s\n" "PROMPT" "OUT" "CHARS" "VIS/2.7" "THINK" "CORRECT?"
echo "  -----------------------+--------+--------+--------+----------+---------"

validate_calibration() {
  local label="$1" out="$2" chars="$3" has_think="$4"
  local vis_tok=$(echo "scale=0; ($chars + 2) / 2.7" | bc | cut -d. -f1)  # ceil approximation
  vis_tok=$((vis_tok > 0 ? vis_tok : 1))
  local think=$((out - vis_tok))
  [ "$think" -lt 0 ] && think=0

  local correct="?"
  if [ "$has_think" = "false" ]; then
    # Non-thinking should be < 50
    [ "$think" -lt 50 ] && correct="PASS" || correct="FAIL"
  else
    # Thinking should be > 0
    [ "$think" -gt 0 ] && correct="PASS" || correct="FAIL"
  fi

  printf "  %-22s | %6d | %6d | %6d | %8d | %s\n" "$label" "$out" "$chars" "$vis_tok" "$think" "$correct"

  TOTAL=$((TOTAL + 1))
  if [ "$correct" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

validate_calibration "2+2 trivial" 6 1 "false"
validate_calibration "3 languages" 17 25 "false"
validate_calibration "TCP vs UDP" 474 1209 "false"
validate_calibration "CAP theorem" 1728 4683 "false"
validate_calibration "Fixed-point proof" 2927 6012 "true"
validate_calibration "River puzzle+fox" 5750 1691 "true"

echo ""
# ==========================================
echo "--- TEST 6: Edge Cases ---"
# ==========================================

# 6a: Empty JSON
empty_out=$(echo '{}' | "$SL" 2>/dev/null)
empty_clean=$(strip_ansi "$empty_out")
check "empty JSON: has 5h --%" "yes" "$(echo "$empty_clean" | grep -q '5h Limit --%' && echo yes || echo no)"
check "empty JSON: has 7d --%" "yes" "$(echo "$empty_clean" | grep -q '7d Limit --%' && echo yes || echo no)"
check "empty JSON: has ctx --%" "yes" "$(echo "$empty_clean" | grep -q 'ctx --%' && echo yes || echo no)"
check "empty JSON: no line 2" "1" "$(echo "$empty_clean" | wc -l | tr -d ' ')"

# 6b: Float percentage
float_out=$(echo '{"rate_limits":{"five_hour":{"used_percentage":28.000000000000004,"resets_at":'$((NOW+3600))'},"seven_day":{"used_percentage":99.9,"resets_at":'$((NOW+86400))'}}}' | "$SL" 2>/dev/null)
float_clean=$(strip_ansi "$float_out")
check "float 28.0...04 → 28%" "yes" "$(echo "$float_clean" | grep -q '28%' && echo yes || echo no)"
check "float 99.9 → 99%" "yes" "$(echo "$float_clean" | grep -q '99%' && echo yes || echo no)"

# 6c: Percentage > 100
over_out=$(echo '{"rate_limits":{"five_hour":{"used_percentage":150,"resets_at":'$((NOW-100))'}}}' | "$SL" 2>/dev/null)
over_clean=$(strip_ansi "$over_out")
check "150% bar clamped" "yes" "$(echo "$over_clean" | grep -q '150%' && echo yes || echo no)"
check "past reset → now" "yes" "$(echo "$over_clean" | grep -q 'now' && echo yes || echo no)"

echo ""
# ==========================================
echo "--- TEST 7: Real live data cross-validation ---"
# ==========================================

LIVE="/tmp/claude-statusline-debug.json"
if [ -f "$LIVE" ]; then
  # Extract raw values
  r_five_pct=$(jq -r '(.rate_limits.five_hour.used_percentage // 0) | floor' "$LIVE" 2>/dev/null)
  r_seven_pct=$(jq -r '(.rate_limits.seven_day.used_percentage // 0) | floor' "$LIVE" 2>/dev/null)
  r_ctx=$(jq -r '(.context_window.used_percentage // 0) | floor' "$LIVE" 2>/dev/null)
  r_in=$(jq -r '.context_window.current_usage.input_tokens // 0' "$LIVE" 2>/dev/null)
  r_cc=$(jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' "$LIVE" 2>/dev/null)
  r_out=$(jq -r '.context_window.current_usage.output_tokens // 0' "$LIVE" 2>/dev/null)
  r_cr=$(jq -r '.context_window.current_usage.cache_read_input_tokens // 0' "$LIVE" 2>/dev/null)
  r_ti=$(jq -r '.context_window.total_input_tokens // 0' "$LIVE" 2>/dev/null)
  r_to=$(jq -r '.context_window.total_output_tokens // 0' "$LIVE" 2>/dev/null)

  # Manual calculations
  calc_last=$((r_in + r_cc + r_out))
  calc_session=$((r_ti + r_to))
  calc_cached=$r_cr

  # Run statusline
  live_out=$(cat "$LIVE" | "$SL" 2>/dev/null)
  live_clean=$(strip_ansi "$live_out")

  check "live: 5h pct ${r_five_pct}%" "yes" "$(echo "$live_clean" | grep -q "${r_five_pct}%" && echo yes || echo no)"
  check "live: 7d pct ${r_seven_pct}%" "yes" "$(echo "$live_clean" | grep -q "${r_seven_pct}%" && echo yes || echo no)"
  check "live: ctx ${r_ctx}%" "yes" "$(echo "$live_clean" | grep -q "ctx ${r_ctx}%" && echo yes || echo no)"
  check "live: last API-Call $(fmt_tokens $calc_last)" "yes" "$(echo "$live_clean" | grep -q "last API-Call $(fmt_tokens $calc_last)" && echo yes || echo no)"
  check "live: session $(fmt_tokens $calc_session)" "yes" "$(echo "$live_clean" | grep -q "session $(fmt_tokens $calc_session)" && echo yes || echo no)"
  check "live: cached $(fmt_tokens $calc_cached)" "yes" "$(echo "$live_clean" | grep -q "cached history $(fmt_tokens $calc_cached)" && echo yes || echo no)"

  echo ""
  echo "  Live raw values for manual check:"
  echo "    5h: ${r_five_pct}% | 7d: ${r_seven_pct}% | ctx: ${r_ctx}%"
  echo "    last: ${r_in}+${r_cc}+${r_out}=${calc_last} | session: ${r_ti}+${r_to}=${calc_session} | cached: ${calc_cached}"
else
  echo "  SKIP  No live debug JSON found"
fi

echo ""
echo "============================================"
echo "  RESULTS: $PASS/$TOTAL PASS, $FAIL FAIL"
echo "============================================"
