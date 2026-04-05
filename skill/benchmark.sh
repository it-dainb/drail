#!/usr/bin/env bash
# Benchmark: drail skill vs no-skill
# Measures: tool calls, tokens (input/output), wall-clock runtime
# Runs each prompt twice: with skill (normal) and without (bare/help-only)

set -euo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
DRAIL_BIN="$(which drail 2>/dev/null || echo "$DRAIL_DIR/target/debug/drail")"
SKILL_DIR="$DRAIL_DIR/skill"
RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results"
mkdir -p "$RESULTS_DIR"

# Skill content (strip frontmatter)
SKILL_CONTENT=$(sed '/^---$/,/^---$/d' "$SKILL_DIR/SKILL.md")

# Prompts that test code navigation tasks drail was designed for
PROMPTS=(
  "Using drail CLI at $DRAIL_BIN, find all symbol definitions of 'run' in the src/commands directory of $DRAIL_DIR. Show me what you find."
  "Using drail CLI at $DRAIL_BIN, give me a structural map of the $DRAIL_DIR/src directory, then find files matching '*.rs' in src/output."
  "Using drail CLI at $DRAIL_BIN, search for the text 'budget' in $DRAIL_DIR/src, then read the file $DRAIL_DIR/src/budget.rs."
  "Using drail CLI at $DRAIL_BIN, scan the $DRAIL_DIR/src/commands directory for .rs files containing 'pub fn run' and show outlines of matching files."
  "Using drail CLI at $DRAIL_BIN, check the dependencies of $DRAIL_DIR/src/main.rs and find callers of 'dispatch' in $DRAIL_DIR/src."
)

PROMPT_NAMES=(
  "symbol_find"
  "map_and_files"
  "search_and_read"
  "scan_composite"
  "deps_and_callers"
)

# Extract metrics from stream-json output (--verbose format)
extract_metrics() {
  local json_file="$1"

  # Count tool_use content blocks
  local tool_calls
  tool_calls=$(grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' "$json_file" 2>/dev/null | wc -l)
  tool_calls=${tool_calls:-0}

  # Get the last (final) usage block's tokens - these are cumulative
  local input_tokens
  input_tokens=$(grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  input_tokens=${input_tokens:-0}

  local output_tokens
  output_tokens=$(grep -o '"output_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  output_tokens=${output_tokens:-0}

  local cache_read
  cache_read=$(grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_read=${cache_read:-0}

  local cache_create
  cache_create=$(grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_create=${cache_create:-0}

  # Count turns (assistant messages)
  local turns
  turns=$(grep -o '"type"[[:space:]]*:[[:space:]]*"assistant"' "$json_file" 2>/dev/null | wc -l)
  turns=${turns:-0}

  echo "$tool_calls $input_tokens $output_tokens $cache_read $cache_create $turns"
}

echo "============================================="
echo "  drail Skill Benchmark"
echo "  $(date)"
echo "============================================="
echo ""
echo "Running ${#PROMPTS[@]} prompts x 2 modes (with-skill, no-skill)"
echo "Model: sonnet (via claude -p --bare)"
echo ""

# CSV header
CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,mode,tool_calls,input_tokens,output_tokens,cache_read,cache_create,turns,wall_seconds" > "$CSV"

# Summary accumulators
declare -a SKILL_TOOLS=() SKILL_INPUT=() SKILL_OUTPUT=() SKILL_TIME=() SKILL_TURNS=()
declare -a BARE_TOOLS=() BARE_INPUT=() BARE_OUTPUT=() BARE_TIME=() BARE_TURNS=()

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"

  echo "--- Prompt $((i+1))/${#PROMPTS[@]}: $name ---"

  # ---- WITH SKILL ----
  echo -n "  [with-skill] running... "
  out_skill="$RESULTS_DIR/${name}_skill.jsonl"

  start_skill=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "Bash" \
    --append-system-prompt "You have access to drail CLI at $DRAIL_BIN. Use it for all code navigation tasks. Be concise.

$SKILL_CONTENT" \
    > "$out_skill" 2>/dev/null || true
  end_skill=$(date +%s%N)

  wall_skill=$(( (end_skill - start_skill) / 1000000000 ))
  read -r tc_s it_s ot_s cr_s cc_s tu_s <<< "$(extract_metrics "$out_skill")"

  SKILL_TOOLS+=("$tc_s"); SKILL_INPUT+=("$it_s"); SKILL_OUTPUT+=("$ot_s"); SKILL_TIME+=("$wall_skill"); SKILL_TURNS+=("$tu_s")
  echo "${tc_s} tools, ${tu_s} turns, ${it_s}in+${ot_s}out tokens, ${wall_skill}s"
  echo "$name,with-skill,$tc_s,$it_s,$ot_s,$cr_s,$cc_s,$tu_s,$wall_skill" >> "$CSV"

  # ---- WITHOUT SKILL (bare) ----
  echo -n "  [no-skill]   running... "
  out_bare="$RESULTS_DIR/${name}_bare.jsonl"

  start_bare=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "Bash" \
    --append-system-prompt "You have access to drail CLI at $DRAIL_BIN. Use it for all code navigation tasks. Be concise. Run drail --help and drail <command> --help to learn the CLI commands." \
    > "$out_bare" 2>/dev/null || true
  end_bare=$(date +%s%N)

  wall_bare=$(( (end_bare - start_bare) / 1000000000 ))
  read -r tc_b it_b ot_b cr_b cc_b tu_b <<< "$(extract_metrics "$out_bare")"

  BARE_TOOLS+=("$tc_b"); BARE_INPUT+=("$it_b"); BARE_OUTPUT+=("$ot_b"); BARE_TIME+=("$wall_bare"); BARE_TURNS+=("$tu_b")
  echo "${tc_b} tools, ${tu_b} turns, ${it_b}in+${ot_b}out tokens, ${wall_bare}s"
  echo "$name,no-skill,$tc_b,$it_b,$ot_b,$cr_b,$cc_b,$tu_b,$wall_bare" >> "$CSV"

  echo ""
done

# ---- SUMMARY ----
echo "============================================="
echo "  SUMMARY"
echo "============================================="

sum() { local s=0; for v in "$@"; do s=$((s + v)); done; echo $s; }
avg() { local s=0; local n=$#; for v in "$@"; do s=$((s + v)); done; echo $((s / n)); }

total_skill_tools=$(sum "${SKILL_TOOLS[@]}")
total_bare_tools=$(sum "${BARE_TOOLS[@]}")
total_skill_input=$(sum "${SKILL_INPUT[@]}")
total_bare_input=$(sum "${BARE_INPUT[@]}")
total_skill_output=$(sum "${SKILL_OUTPUT[@]}")
total_bare_output=$(sum "${BARE_OUTPUT[@]}")
total_skill_time=$(sum "${SKILL_TIME[@]}")
total_bare_time=$(sum "${BARE_TIME[@]}")
total_skill_turns=$(sum "${SKILL_TURNS[@]}")
total_bare_turns=$(sum "${BARE_TURNS[@]}")

avg_skill_tools=$(avg "${SKILL_TOOLS[@]}")
avg_bare_tools=$(avg "${BARE_TOOLS[@]}")
avg_skill_time=$(avg "${SKILL_TIME[@]}")
avg_bare_time=$(avg "${BARE_TIME[@]}")

printf "\n%-22s %15s %15s %10s\n" "Metric" "With Skill" "No Skill" "Delta"
printf "%-22s %15s %15s %10s\n" "----------------------" "---------------" "---------------" "----------"
printf "%-22s %15d %15d %+10d\n" "Total tool calls" "$total_skill_tools" "$total_bare_tools" "$((total_skill_tools - total_bare_tools))"
printf "%-22s %15d %15d %+10d\n" "Avg tool calls" "$avg_skill_tools" "$avg_bare_tools" "$((avg_skill_tools - avg_bare_tools))"
printf "%-22s %15d %15d %+10d\n" "Total turns" "$total_skill_turns" "$total_bare_turns" "$((total_skill_turns - total_bare_turns))"
printf "%-22s %15d %15d %+10d\n" "Total input tokens" "$total_skill_input" "$total_bare_input" "$((total_skill_input - total_bare_input))"
printf "%-22s %15d %15d %+10d\n" "Total output tokens" "$total_skill_output" "$total_bare_output" "$((total_skill_output - total_bare_output))"
printf "%-22s %15d %15d %+10d\n" "Total wall time (s)" "$total_skill_time" "$total_bare_time" "$((total_skill_time - total_bare_time))"
printf "%-22s %15d %15d %+10d\n" "Avg wall time (s)" "$avg_skill_time" "$avg_bare_time" "$((avg_skill_time - avg_bare_time))"

# Percentage improvements
echo ""
echo "--- Improvement (positive = skill is better) ---"
if [ "$total_bare_tools" -gt 0 ]; then
  tool_pct=$(( (total_bare_tools - total_skill_tools) * 100 / total_bare_tools ))
  echo "Tool call reduction:   ${tool_pct}%"
fi
if [ "$total_bare_output" -gt 0 ]; then
  token_pct=$(( (total_bare_output - total_skill_output) * 100 / total_bare_output ))
  echo "Output token reduction: ${token_pct}%"
fi
if [ "$total_bare_input" -gt 0 ]; then
  input_pct=$(( (total_bare_input - total_skill_input) * 100 / total_bare_input ))
  echo "Input token reduction:  ${input_pct}%"
fi
if [ "$total_bare_time" -gt 0 ]; then
  time_pct=$(( (total_bare_time - total_skill_time) * 100 / total_bare_time ))
  echo "Wall time reduction:    ${time_pct}%"
fi

echo ""
echo "--- Per-prompt breakdown ---"
printf "%-18s | %6s %6s | %6s %6s | %7s %7s | %5s %5s\n" \
  "Prompt" "Tools" "Tools" "OutTok" "OutTok" "Time" "Time" "Turns" "Turns"
printf "%-18s | %6s %6s | %6s %6s | %7s %7s | %5s %5s\n" \
  "" "skill" "bare" "skill" "bare" "skill" "bare" "skill" "bare"
printf "%-18s-+-%6s-%6s-+-%6s-%6s-+-%7s-%7s-+-%5s-%5s\n" \
  "------------------" "------" "------" "------" "------" "-------" "-------" "-----" "-----"
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-18s | %6d %6d | %6d %6d | %7d %7d | %5d %5d\n" \
    "${PROMPT_NAMES[$i]}" \
    "${SKILL_TOOLS[$i]}" "${BARE_TOOLS[$i]}" \
    "${SKILL_OUTPUT[$i]}" "${BARE_OUTPUT[$i]}" \
    "${SKILL_TIME[$i]}" "${BARE_TIME[$i]}" \
    "${SKILL_TURNS[$i]}" "${BARE_TURNS[$i]}"
done

echo ""
echo "Raw CSV: $CSV"
echo "Raw JSONL files: $RESULTS_DIR/"
