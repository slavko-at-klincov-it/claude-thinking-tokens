#!/bin/bash
# Claude Code Status Line: Rate Limits + Token Usage (two lines)
#
# Line 1: 5h Limit ██░░░░░░░░ 19% 1h32m | 7d Limit ██░░░░░░░░ 20% Fr 11:00 | ctx 4%
# Line 2: last API-Call 724 | session 36.5k | cached history 75.6k
# Line 3: thinking: ON ████░░░░░░ ~5.4k this turn (heavy, 8/15 calls)
#
# "last API-Call" = new tokens (input + cache_creation + output), excludes cache reads
# "cached history" = cache_read_input_tokens (conversation history reused from cache)
# "thinking" = AGGREGATED across entire turn (all API calls since last user message)
#              Not just the last call! Heavy thinking often happens in earlier calls.
#              = SUM of (output_tokens - visible_tokens) across all calls in the turn
#              Calibrated: ~2.7 chars/token for markdown (verified: non-thinking → ~0).

BAR_WIDTH=10
THINKING_CAP=128000

input=$(cat)
echo "$input" > /tmp/claude-statusline-debug.json

# --- Helper: format token count (42, 1.5k, 18.0k) ---
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

# --- Helper: build colored bar from percentage ---
build_bar() {
  local pct=$1
  local filled=$(( (pct * BAR_WIDTH) / 100 ))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  local empty=$(( BAR_WIDTH - filled ))

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  local color
  if [ "$pct" -le 40 ]; then
    color="\033[32m"     # green
  elif [ "$pct" -le 70 ]; then
    color="\033[33m"     # yellow
  elif [ "$pct" -le 90 ]; then
    color="\033[31m"     # red
  else
    color="\033[1;31m"   # bold red
  fi

  printf "${color}${bar} %d%%\033[0m" "$pct"
}

# --- Extract values via jq ---
five_pct=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | floor' 2>/dev/null)
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
seven_pct=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | floor' 2>/dev/null)
seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
ctx_pct=$(echo "$input" | jq -r '(.context_window.used_percentage // empty) | floor' 2>/dev/null)
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty' 2>/dev/null)
turn_new=$(echo "$input" | jq -r '
  .context_window.current_usage |
  if . != null then
    ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0))
  else empty end
' 2>/dev/null)
turn_cached=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty' 2>/dev/null)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# --- Thinking: per prompt (all API calls since last user message) ---
# Bar + number = total thinking for current prompt response
# X/Y calls = how many of those calls used thinking
think_active=""
think_est=""
think_calls=""
think_total_calls=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  think_data=$(tail -n 500 "$transcript_path" 2>/dev/null | jq -rs '
    (to_entries | map(select(.value.type == "user" and (.value.message.content | type) == "string")) | last | .key // -1) as $last_prompt |
    [to_entries[] | select(.key > $last_prompt and .value.type == "assistant" and .value.message.usage.output_tokens != null) | .value] |
    if length == 0 then "||||"
    else
      group_by(.requestId) |
      map({
        out: (.[0].message.usage.output_tokens),
        has_think: ([.[] | .message.content[]? | select(.type == "thinking")] | length > 0),
        vis: ([(.[] | .message.content[]? | select(.type == "text") | .text // "" | length), (.[] | .message.content[]? | select(.type == "tool_use") | .input // {} | tostring | length)] | add // 0)
      }) |
      (map(select(.has_think)) | length) as $think_calls |
      (length) as $total_calls |
      (map(.out) | add) as $total_out |
      (map(.vis) | add // 0) as $total_vis |
      ($total_vis / 2.7 | ceil) as $vis_tok |
      ($total_out - $vis_tok) as $think_raw |
      (if $think_raw < 0 then 0 else $think_raw end) as $think |
      ($think_calls > 0) as $any_think |
      "\($any_think)|\($think)|\($think_calls)|\($total_calls)"
    end
  ' 2>/dev/null)

  IFS='|' read -r think_active think_est think_calls think_total_calls <<< "$think_data"
fi

# --- 5h segment ---
if [ -n "$five_pct" ]; then
  five_bar=$(build_bar "$five_pct")
  if [ -n "$five_resets" ]; then
    now=$(date +%s)
    diff=$(( five_resets - now ))
    if [ "$diff" -le 0 ]; then
      five_time="now"
    else
      hours=$(( diff / 3600 ))
      mins=$(( (diff % 3600) / 60 ))
      if [ "$hours" -gt 0 ]; then
        five_time="${hours}h${mins}m"
      else
        five_time="${mins}m"
      fi
    fi
  else
    five_time="--"
  fi
  seg_5h="5h Limit ${five_bar} ${five_time}"
else
  seg_5h="5h Limit --%"
fi

# --- 7d segment ---
if [ -n "$seven_pct" ]; then
  seven_bar=$(build_bar "$seven_pct")
  if [ -n "$seven_resets" ]; then
    if [[ "$OSTYPE" == darwin* ]]; then
      seven_time=$(date -r "$seven_resets" "+%a %H:%M")
    else
      seven_time=$(date -d "@$seven_resets" "+%a %H:%M")
    fi
  else
    seven_time="--"
  fi
  seg_7d="7d Limit ${seven_bar} ${seven_time}"
else
  seg_7d="7d Limit --%"
fi

# --- Context segment ---
if [ -n "$ctx_pct" ]; then
  seg_ctx="ctx ${ctx_pct}%"
else
  seg_ctx="ctx --%"
fi

# --- Line 1: Rate limits + context ---
line1="${seg_5h} | ${seg_7d} | ${seg_ctx}"

# --- Line 2: Last API-Call (new tokens) | session | cached history ---
line2=""
if [ -n "$turn_new" ]; then
  line2="last API-Call $(fmt_tokens $turn_new)"
fi

if [ -n "$total_in" ] && [ -n "$total_out" ]; then
  session_total=$(( total_in + total_out ))
  if [ -n "$line2" ]; then
    line2="${line2} | session $(fmt_tokens $session_total)"
  else
    line2="session $(fmt_tokens $session_total)"
  fi
fi

if [ -n "$turn_cached" ]; then
  if [ -n "$line2" ]; then
    line2="${line2} | cached history $(fmt_tokens $turn_cached)"
  else
    line2="cached history $(fmt_tokens $turn_cached)"
  fi
fi

# --- Line 3: Thinking (per prompt, all calls since last user message) ---
line3=""
if [ "$think_active" = "true" ]; then
  if [ -n "$think_est" ] && [ "$think_est" -ge 0 ] 2>/dev/null; then
    think_pct=$(( (think_est * 100) / THINKING_CAP ))
    [ "$think_pct" -gt 100 ] && think_pct=100
    think_bar=$(build_bar "$think_pct")
    line3="\033[32mthinking\033[0m ${think_bar} ~$(fmt_tokens $think_est) (${think_calls}/${think_total_calls} calls)"
  else
    line3="\033[32mthinking\033[0m"
  fi
elif [ "$think_active" = "false" ]; then
  line3="\033[90mthinking: OFF (0/${think_total_calls:-0} calls)\033[0m"
fi

# --- Output ---
out="$line1"
[ -n "$line2" ] && out="${out}"$'\n'"$line2"
[ -n "$line3" ] && out="${out}"$'\n'"$line3"
printf "%b" "$out"
