#!/bin/bash
# Time-based Thinking Analysis
# Run this at different times of day to test if thinking allocation varies with server load.
# Based on findings from github.com/anthropics/claude-code/issues/42796
#
# Usage:
#   ./time-analysis.sh           # Run all 6 prompts, append to CSV
#   ./time-analysis.sh --report  # Show summary of collected data

set -e

CSV="$(dirname "$0")/time-analysis-results.csv"

if [ "$1" = "--report" ]; then
  if [ ! -f "$CSV" ]; then
    echo "No data yet. Run ./time-analysis.sh first (without --report)."
    exit 1
  fi
  echo "=== Time-based Thinking Analysis Report ==="
  echo ""
  echo "Runs collected: $(tail -n +2 "$CSV" | cut -d, -f1 | sort -u | wc -l | tr -d ' ')"
  echo "Total prompts: $(tail -n +2 "$CSV" | wc -l | tr -d ' ')"
  echo ""
  echo "--- Thinking rate by hour (local time) ---"
  tail -n +2 "$CSV" | awk -F, '{
    hour = substr($2, 1, 2)
    total[hour]++
    if ($5 == "true") think[hour]++
    out_sum[hour] += $4
  } END {
    for (h in total) {
      t = (think[h] ? think[h] : 0)
      printf "  %s:00  %d/%d thinking (%d%%)  avg_out: %d\n", h, t, total[h], (t*100/total[h]), (out_sum[h]/total[h])
    }
  }' | sort
  echo ""
  echo "--- Average output_tokens by hour ---"
  tail -n +2 "$CSV" | awk -F, '{
    hour = substr($2, 1, 2)
    sum[hour] += $4
    count[hour]++
  } END {
    for (h in sum) printf "  %s:00  avg %d tokens\n", h, sum[h]/count[h]
  }' | sort
  echo ""
  echo "--- Max signature by hour ---"
  tail -n +2 "$CSV" | awk -F, '{
    hour = substr($2, 1, 2)
    if ($6 > max_sig[hour]) max_sig[hour] = $6
  } END {
    for (h in max_sig) printf "  %s:00  max_sig %d\n", h, max_sig[h]
  }' | sort
  echo ""
  echo "Raw data: $CSV"
  exit 0
fi

# --- Run prompts ---
echo "Running 6 prompts at $(date '+%Y-%m-%d %H:%M:%S %Z')..."

# Create CSV header if needed
if [ ! -f "$CSV" ]; then
  echo "run_id,local_time,prompt,output_tokens,has_thinking,max_signature,text_chars" > "$CSV"
fi

RUN_ID=$(date +%s)
LOCAL_TIME=$(date '+%H:%M')

PROMPTS=(
  "What is 2+2?"
  "Name 3 programming languages."
  "Explain the difference between TCP and UDP in networking."
  "Compare and contrast the CAP theorem implications for PostgreSQL vs Cassandra vs CockroachDB. Include specific failure scenarios and trade-offs for each."
  "Think extremely deeply. Prove or disprove: every continuous function from a closed interval to itself has a fixed point. Consider multiple proof approaches, edge cases, and generalizations to higher dimensions."
  "A farmer has a wolf, a goat, and a cabbage. He must cross a river with a boat that can only carry him and one item. If left alone, the wolf eats the goat, and the goat eats the cabbage. But there's a twist: there are TWO rivers to cross, and in between the rivers there's an island where a fox lives that will eat the goat if the farmer isn't present. How can the farmer get everything across both rivers safely? Think through every possible state."
)

LABELS=(
  "trivial_2plus2"
  "simple_languages"
  "medium_tcp_udp"
  "complex_cap_theorem"
  "hard_fixed_point"
  "hard_river_puzzle"
)

for i in "${!PROMPTS[@]}"; do
  label="${LABELS[$i]}"
  echo "  [$((i+1))/6] $label..."

  # Run prompt
  claude -p "${PROMPTS[$i]}" 2>/dev/null > /dev/null

  # Find the most recent transcript
  t=$(find ~/.claude/projects/ -name "*.jsonl" -mmin -2 -maxdepth 3 2>/dev/null | sort -t/ -k6 | tail -1)

  if [ -n "$t" ]; then
    # Extract data
    data=$(grep '"type":"assistant"' "$t" 2>/dev/null | jq -rs '
      group_by(.requestId) | map(.[0]) | .[0] |
      {
        out: .message.usage.output_tokens,
        think: ([.message.content[]? | select(.type=="thinking")] | length > 0),
        sig: ([.message.content[]? | select(.type=="thinking") | .signature // "" | length] | if length > 0 then max else 0 end),
        text: ([.message.content[]? | select(.type=="text") | .text // "" | length] | add // 0)
      } | "\(.out),\(.think),\(.sig),\(.text)"
    ' 2>/dev/null)

    echo "${RUN_ID},${LOCAL_TIME},${label},${data}" >> "$CSV"
  else
    echo "${RUN_ID},${LOCAL_TIME},${label},0,false,0,0" >> "$CSV"
  fi
done

echo ""
echo "Done. Results appended to $CSV"
echo "Run at different times of day, then: ./time-analysis.sh --report"
