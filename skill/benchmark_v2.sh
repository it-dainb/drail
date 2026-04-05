#!/usr/bin/env bash
# Benchmark: drail+skill vs native Claude tools (Read, Glob, Grep)
# Measures: tool calls, tokens (input/output), wall-clock runtime
# "with-drail" = drail CLI + skill instructions
# "native" = standard Claude tools (Read, Glob, Grep, Bash)

set -euo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
DRAIL_BIN="$(which drail 2>/dev/null || echo "$DRAIL_DIR/target/debug/drail")"
SKILL_DIR="$DRAIL_DIR/skill"
RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_v2"
mkdir -p "$RESULTS_DIR"

# Skill content (strip frontmatter)
SKILL_CONTENT=$(sed '/^---$/,/^---$/d' "$SKILL_DIR/SKILL.md")

# Task descriptions — same goal, tool-agnostic phrasing
PROMPTS=(
  "Find all definitions of the function 'run' in $DRAIL_DIR/src/commands/. Show the function signatures and which files they are in."
  "Give me a structural overview of $DRAIL_DIR/src/ — what modules exist, how they're organized. Then list all .rs files in src/output/."
  "Search for the word 'budget' across all files in $DRAIL_DIR/src/. Then show me the contents of $DRAIL_DIR/src/budget.rs."
  "In $DRAIL_DIR/src/commands/, find all .rs files that contain 'pub fn run'. For each matching file, show me a structural outline of that file."
  "Show me what $DRAIL_DIR/src/main.rs imports and what other files import it. Then find all call sites of the function 'dispatch' in $DRAIL_DIR/src/."
)

PROMPT_NAMES=(
  "find_fn_defs"
  "codebase_overview"
  "search_and_read"
  "find_and_outline"
  "deps_and_callers"
)

# Extract metrics from stream-json output
extract_metrics() {
  local json_file="$1"

  local tool_calls
  tool_calls=$(grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' "$json_file" 2>/dev/null | wc -l)
  tool_calls=${tool_calls:-0}

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

  local turns
  turns=$(grep -o '"type"[[:space:]]*:[[:space:]]*"assistant"' "$json_file" 2>/dev/null | wc -l)
  turns=${turns:-0}

  echo "$tool_calls $input_tokens $output_tokens $cache_read $cache_create $turns"
}

echo "============================================="
echo "  drail vs Native Tools Benchmark"
echo "  $(date)"
echo "============================================="
echo ""
echo "Running ${#PROMPTS[@]} prompts x 2 modes"
echo "  [drail]  = drail CLI + skill (Bash only)"
echo "  [native] = Read, Glob, Grep, Bash"
echo "Model: sonnet (via claude -p --bare)"
echo ""

# CSV header
CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,mode,tool_calls,input_tokens,output_tokens,cache_read,cache_create,turns,wall_seconds" > "$CSV"

# Summary accumulators
declare -a DRAIL_TOOLS=() DRAIL_INPUT=() DRAIL_OUTPUT=() DRAIL_TIME=() DRAIL_TURNS=()
declare -a NATIVE_TOOLS=() NATIVE_INPUT=() NATIVE_OUTPUT=() NATIVE_TIME=() NATIVE_TURNS=()

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"

  echo "--- Prompt $((i+1))/${#PROMPTS[@]}: $name ---"

  # ---- WITH DRAIL + SKILL ----
  echo -n "  [drail]  running... "
  out_drail="$RESULTS_DIR/${name}_drail.jsonl"

  start_drail=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "Bash" \
    --append-system-prompt "You have access to drail CLI (installed globally as 'drail'). Use drail for ALL code navigation tasks instead of other tools. Be concise. Do not use Read, Glob, or Grep tools — use drail commands exclusively.

$SKILL_CONTENT" \
    > "$out_drail" 2>/dev/null || true
  end_drail=$(date +%s%N)

  wall_drail=$(( (end_drail - start_drail) / 1000000000 ))
  read -r tc_d it_d ot_d cr_d cc_d tu_d <<< "$(extract_metrics "$out_drail")"

  DRAIL_TOOLS+=("$tc_d"); DRAIL_INPUT+=("$it_d"); DRAIL_OUTPUT+=("$ot_d"); DRAIL_TIME+=("$wall_drail"); DRAIL_TURNS+=("$tu_d")
  echo "${tc_d} tools, ${tu_d} turns, ${it_d}in+${ot_d}out tokens, ${wall_drail}s"
  echo "$name,drail,$tc_d,$it_d,$ot_d,$cr_d,$cc_d,$tu_d,$wall_drail" >> "$CSV"

  # ---- NATIVE TOOLS (Read, Glob, Grep, Bash) ----
  echo -n "  [native] running... "
  out_native="$RESULTS_DIR/${name}_native.jsonl"

  start_native=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "Read,Glob,Grep,Bash" \
    --append-system-prompt "Use Read, Glob, and Grep tools for code navigation. Be concise." \
    > "$out_native" 2>/dev/null || true
  end_native=$(date +%s%N)

  wall_native=$(( (end_native - start_native) / 1000000000 ))
  read -r tc_n it_n ot_n cr_n cc_n tu_n <<< "$(extract_metrics "$out_native")"

  NATIVE_TOOLS+=("$tc_n"); NATIVE_INPUT+=("$it_n"); NATIVE_OUTPUT+=("$ot_n"); NATIVE_TIME+=("$wall_native"); NATIVE_TURNS+=("$tu_n")
  echo "${tc_n} tools, ${tu_n} turns, ${it_n}in+${ot_n}out tokens, ${wall_native}s"
  echo "$name,native,$tc_n,$it_n,$ot_n,$cr_n,$cc_n,$tu_n,$wall_native" >> "$CSV"

  echo ""
done

# ---- SUMMARY ----
echo "============================================="
echo "  SUMMARY"
echo "============================================="

sum() { local s=0; for v in "$@"; do s=$((s + v)); done; echo $s; }
avg() { local s=0; local n=$#; for v in "$@"; do s=$((s + v)); done; echo $((s / n)); }

total_drail_tools=$(sum "${DRAIL_TOOLS[@]}")
total_native_tools=$(sum "${NATIVE_TOOLS[@]}")
total_drail_input=$(sum "${DRAIL_INPUT[@]}")
total_native_input=$(sum "${NATIVE_INPUT[@]}")
total_drail_output=$(sum "${DRAIL_OUTPUT[@]}")
total_native_output=$(sum "${NATIVE_OUTPUT[@]}")
total_drail_time=$(sum "${DRAIL_TIME[@]}")
total_native_time=$(sum "${NATIVE_TIME[@]}")
total_drail_turns=$(sum "${DRAIL_TURNS[@]}")
total_native_turns=$(sum "${NATIVE_TURNS[@]}")

avg_drail_tools=$(avg "${DRAIL_TOOLS[@]}")
avg_native_tools=$(avg "${NATIVE_TOOLS[@]}")
avg_drail_time=$(avg "${DRAIL_TIME[@]}")
avg_native_time=$(avg "${NATIVE_TIME[@]}")

printf "\n%-22s %15s %15s %10s\n" "Metric" "drail" "Native" "Delta"
printf "%-22s %15s %15s %10s\n" "----------------------" "---------------" "---------------" "----------"
printf "%-22s %15d %15d %+10d\n" "Total tool calls" "$total_drail_tools" "$total_native_tools" "$((total_drail_tools - total_native_tools))"
printf "%-22s %15d %15d %+10d\n" "Avg tool calls" "$avg_drail_tools" "$avg_native_tools" "$((avg_drail_tools - avg_native_tools))"
printf "%-22s %15d %15d %+10d\n" "Total turns" "$total_drail_turns" "$total_native_turns" "$((total_drail_turns - total_native_turns))"
printf "%-22s %15d %15d %+10d\n" "Total input tokens" "$total_drail_input" "$total_native_input" "$((total_drail_input - total_native_input))"
printf "%-22s %15d %15d %+10d\n" "Total output tokens" "$total_drail_output" "$total_native_output" "$((total_drail_output - total_native_output))"
printf "%-22s %15d %15d %+10d\n" "Total wall time (s)" "$total_drail_time" "$total_native_time" "$((total_drail_time - total_native_time))"
printf "%-22s %15d %15d %+10d\n" "Avg wall time (s)" "$avg_drail_time" "$avg_native_time" "$((avg_drail_time - avg_native_time))"

# Percentage differences (positive = drail uses fewer)
echo ""
echo "--- Difference (positive = drail is more efficient) ---"
if [ "$total_native_tools" -gt 0 ]; then
  tool_pct=$(( (total_native_tools - total_drail_tools) * 100 / total_native_tools ))
  echo "Tool call reduction:    ${tool_pct}%"
fi
if [ "$total_native_output" -gt 0 ]; then
  token_pct=$(( (total_native_output - total_drail_output) * 100 / total_native_output ))
  echo "Output token reduction: ${token_pct}%"
fi
if [ "$total_native_input" -gt 0 ]; then
  input_pct=$(( (total_native_input - total_drail_input) * 100 / total_native_input ))
  echo "Input token reduction:  ${input_pct}%"
fi
if [ "$total_native_time" -gt 0 ]; then
  time_pct=$(( (total_native_time - total_drail_time) * 100 / total_native_time ))
  echo "Wall time reduction:    ${time_pct}%"
fi

echo ""
echo "--- Per-prompt breakdown ---"
printf "%-18s | %-6s %-6s | %-6s %-6s | %-7s %-7s | %-5s %-5s\n" \
  "Prompt" "Tools" "Tools" "OutTok" "OutTok" "Time" "Time" "Turns" "Turns"
printf "%-18s | %-6s %-6s | %-6s %-6s | %-7s %-7s | %-5s %-5s\n" \
  "" "drail" "native" "drail" "native" "drail" "native" "drail" "native"
printf "%-18s-+-%-6s-%-6s-+-%-6s-%-6s-+-%-7s-%-7s-+-%-5s-%-5s\n" \
  "------------------" "------" "------" "------" "------" "-------" "-------" "-----" "-----"
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-18s | %6d %6d | %6d %6d | %7d %7d | %5d %5d\n" \
    "${PROMPT_NAMES[$i]}" \
    "${DRAIL_TOOLS[$i]}" "${NATIVE_TOOLS[$i]}" \
    "${DRAIL_OUTPUT[$i]}" "${NATIVE_OUTPUT[$i]}" \
    "${DRAIL_TIME[$i]}" "${NATIVE_TIME[$i]}" \
    "${DRAIL_TURNS[$i]}" "${NATIVE_TURNS[$i]}"
done

echo ""
echo "Raw CSV: $CSV"
echo "Raw JSONL files: $RESULTS_DIR/"
