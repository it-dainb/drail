#!/usr/bin/env bash
# Benchmark: drail skill loaded vs no skill
# FAIR TEST: Both modes get identical tools (Read, Glob, Grep, Bash) and identical prompts.
# The ONLY difference: drail mode has the skill content appended to the system prompt.
# If the skill is effective, Sonnet will naturally discover and prioritize drail.

set -euo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
SKILL_DIR="$DRAIL_DIR/skill"
RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_v3"
mkdir -p "$RESULTS_DIR"

# Skill content (strip frontmatter)
SKILL_CONTENT=$(sed '/^---$/,/^---$/d' "$SKILL_DIR/SKILL.md")

# Task descriptions — tool-agnostic, no hints about what to use
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

# Shared tools — both modes get everything
TOOLS="Read,Glob,Grep,Bash"

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

  # Count which tools were actually used
  local bash_calls
  bash_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Bash"' "$json_file" 2>/dev/null | wc -l)
  bash_calls=${bash_calls:-0}

  local read_calls
  read_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Read"' "$json_file" 2>/dev/null | wc -l)
  read_calls=${read_calls:-0}

  local glob_calls
  glob_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Glob"' "$json_file" 2>/dev/null | wc -l)
  glob_calls=${glob_calls:-0}

  local grep_calls
  grep_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Grep"' "$json_file" 2>/dev/null | wc -l)
  grep_calls=${grep_calls:-0}

  echo "$tool_calls $input_tokens $output_tokens $cache_read $cache_create $turns $bash_calls $read_calls $glob_calls $grep_calls"
}

echo "============================================="
echo "  drail Skill vs No Skill (Fair Test)"
echo "  $(date)"
echo "============================================="
echo ""
echo "Running ${#PROMPTS[@]} prompts x 2 modes"
echo "  [skill]    = skill loaded, same tools ($TOOLS)"
echo "  [no-skill] = no skill, same tools ($TOOLS)"
echo "  Both get identical prompts with NO tool preference hints."
echo "Model: sonnet (via claude -p --bare)"
echo ""

# CSV header
CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,mode,tool_calls,input_tokens,output_tokens,cache_read,cache_create,turns,bash_calls,read_calls,glob_calls,grep_calls,wall_seconds" > "$CSV"

# Summary accumulators
declare -a S_TOOLS=() S_INPUT=() S_OUTPUT=() S_TIME=() S_TURNS=() S_BASH=() S_READ=() S_GLOB=() S_GREP=()
declare -a N_TOOLS=() N_INPUT=() N_OUTPUT=() N_TIME=() N_TURNS=() N_BASH=() N_READ=() N_GLOB=() N_GREP=()

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"

  echo "--- Prompt $((i+1))/${#PROMPTS[@]}: $name ---"

  # ---- WITH SKILL ----
  echo -n "  [skill]    running... "
  out_skill="$RESULTS_DIR/${name}_skill.jsonl"

  start_s=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "$TOOLS" \
    --append-system-prompt "$SKILL_CONTENT" \
    > "$out_skill" 2>/dev/null || true
  end_s=$(date +%s%N)

  wall_s=$(( (end_s - start_s) / 1000000000 ))
  read -r tc it ot cr cc tu ba re gl gr <<< "$(extract_metrics "$out_skill")"

  S_TOOLS+=("$tc"); S_INPUT+=("$it"); S_OUTPUT+=("$ot"); S_TIME+=("$wall_s"); S_TURNS+=("$tu")
  S_BASH+=("$ba"); S_READ+=("$re"); S_GLOB+=("$gl"); S_GREP+=("$gr")
  echo "${tc} tools (bash:${ba} read:${re} glob:${gl} grep:${gr}), ${tu} turns, ${it}in+${ot}out, ${wall_s}s"
  echo "$name,skill,$tc,$it,$ot,$cr,$cc,$tu,$ba,$re,$gl,$gr,$wall_s" >> "$CSV"

  # ---- WITHOUT SKILL ----
  echo -n "  [no-skill] running... "
  out_none="$RESULTS_DIR/${name}_noskill.jsonl"

  start_n=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --bare \
    --allowedTools "$TOOLS" \
    > "$out_none" 2>/dev/null || true
  end_n=$(date +%s%N)

  wall_n=$(( (end_n - start_n) / 1000000000 ))
  read -r tc it ot cr cc tu ba re gl gr <<< "$(extract_metrics "$out_none")"

  N_TOOLS+=("$tc"); N_INPUT+=("$it"); N_OUTPUT+=("$ot"); N_TIME+=("$wall_n"); N_TURNS+=("$tu")
  N_BASH+=("$ba"); N_READ+=("$re"); N_GLOB+=("$gl"); N_GREP+=("$gr")
  echo "${tc} tools (bash:${ba} read:${re} glob:${gl} grep:${gr}), ${tu} turns, ${it}in+${ot}out, ${wall_n}s"
  echo "$name,no-skill,$tc,$it,$ot,$cr,$cc,$tu,$ba,$re,$gl,$gr,$wall_n" >> "$CSV"

  echo ""
done

# ---- SUMMARY ----
echo "============================================="
echo "  SUMMARY"
echo "============================================="

sum() { local s=0; for v in "$@"; do s=$((s + v)); done; echo $s; }
avg() { local s=0; local n=$#; for v in "$@"; do s=$((s + v)); done; echo $((s / n)); }

ts=$(sum "${S_TOOLS[@]}");  tn=$(sum "${N_TOOLS[@]}")
is=$(sum "${S_INPUT[@]}");  in_=$(sum "${N_INPUT[@]}")
os=$(sum "${S_OUTPUT[@]}"); on=$(sum "${N_OUTPUT[@]}")
ws=$(sum "${S_TIME[@]}");   wn=$(sum "${N_TIME[@]}")
us=$(sum "${S_TURNS[@]}");  un=$(sum "${N_TURNS[@]}")
bs=$(sum "${S_BASH[@]}");   bn=$(sum "${N_BASH[@]}")
rs=$(sum "${S_READ[@]}");   rn=$(sum "${N_READ[@]}")
gs=$(sum "${S_GLOB[@]}");   gn=$(sum "${N_GLOB[@]}")
ps=$(sum "${S_GREP[@]}");   pn=$(sum "${N_GREP[@]}")

printf "\n%-22s %15s %15s %10s\n" "Metric" "Skill" "No Skill" "Delta"
printf "%-22s %15s %15s %10s\n" "----------------------" "---------------" "---------------" "----------"
printf "%-22s %15d %15d %+10d\n" "Total tool calls" "$ts" "$tn" "$((ts - tn))"
printf "%-22s %15d %15d %+10d\n" "  Bash calls" "$bs" "$bn" "$((bs - bn))"
printf "%-22s %15d %15d %+10d\n" "  Read calls" "$rs" "$rn" "$((rs - rn))"
printf "%-22s %15d %15d %+10d\n" "  Glob calls" "$gs" "$gn" "$((gs - gn))"
printf "%-22s %15d %15d %+10d\n" "  Grep calls" "$ps" "$pn" "$((ps - pn))"
printf "%-22s %15d %15d %+10d\n" "Total turns" "$us" "$un" "$((us - un))"
printf "%-22s %15d %15d %+10d\n" "Total input tokens" "$is" "$in_" "$((is - in_))"
printf "%-22s %15d %15d %+10d\n" "Total output tokens" "$os" "$on" "$((os - on))"
printf "%-22s %15d %15d %+10d\n" "Total wall time (s)" "$ws" "$wn" "$((ws - wn))"

echo ""
echo "--- Efficiency (positive = skill is better) ---"
[ "$tn" -gt 0 ] && echo "Tool call reduction:    $(( (tn - ts) * 100 / tn ))%"
[ "$on" -gt 0 ] && echo "Output token reduction: $(( (on - os) * 100 / on ))%"
[ "$in_" -gt 0 ] && echo "Input token reduction:  $(( (in_ - is) * 100 / in_ ))%"
[ "$wn" -gt 0 ] && echo "Wall time reduction:    $(( (wn - ws) * 100 / wn ))%"

echo ""
echo "--- Tool adoption (did the model choose drail via Bash?) ---"
echo "Skill mode:    Bash=$bs  Read=$rs  Glob=$gs  Grep=$ps"
echo "No-skill mode: Bash=$bn  Read=$rn  Glob=$gn  Grep=$pn"

echo ""
echo "--- Per-prompt breakdown ---"
printf "%-18s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %-7s %-7s | tool breakdown (skill)\n" \
  "Prompt" "Tools" "Tools" "OutTok" "OutTok" "Turns" "Turns" "Time" "Time"
printf "%-18s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %-7s %-7s |\n" \
  "" "skill" "none" "skill" "none" "skill" "none" "skill" "none"
printf "%-18s-+-%-6s-%-6s-+-%-6s-%-6s-+-%-5s-%-5s-+-%-7s-%-7s-+\n" \
  "------------------" "------" "------" "------" "------" "-----" "-----" "-------" "-------"
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-18s | %6d %6d | %6d %6d | %5d %5d | %7d %7d | B:%d R:%d G:%d P:%d\n" \
    "${PROMPT_NAMES[$i]}" \
    "${S_TOOLS[$i]}" "${N_TOOLS[$i]}" \
    "${S_OUTPUT[$i]}" "${N_OUTPUT[$i]}" \
    "${S_TURNS[$i]}" "${N_TURNS[$i]}" \
    "${S_TIME[$i]}" "${N_TIME[$i]}" \
    "${S_BASH[$i]}" "${S_READ[$i]}" "${S_GLOB[$i]}" "${S_GREP[$i]}"
done

echo ""
echo "Raw CSV: $CSV"
echo "Raw JSONL: $RESULTS_DIR/"
