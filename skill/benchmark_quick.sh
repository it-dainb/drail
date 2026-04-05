#!/usr/bin/env bash
# Quick Benchmark: drail skill — 3 representative prompts for fast iteration
# Full benchmark: benchmark_v4.sh (10 prompts x 2 modes)
#
# Usage:
#   ./benchmark_quick.sh              # Run all 3 prompts, skill + no-skill
#   ./benchmark_quick.sh --skill-only # Run only skill mode (even faster)
#   ./benchmark_quick.sh --run N      # Tag this run as iteration N
#
# Output: skill/benchmark_results_quick/runN/

set -uo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
SKILL_SRC="$DRAIL_DIR/skill"
SKILL_DST="$HOME/.claude/skills/drail"
RUN_TAG="${RUN_TAG:-latest}"
SKILL_ONLY=false

# Parse args
for arg in "$@"; do
  case "$arg" in
    --skill-only) SKILL_ONLY=true ;;
    --run) shift; RUN_TAG="run$1" ;;
    --run=*) RUN_TAG="run${arg#*=}" ;;
  esac
done

RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_quick/$RUN_TAG"
mkdir -p "$RESULTS_DIR"

# Test repo paths
TF="$DRAIL_DIR/skill/tests/transformers/src/transformers"
TRL="$DRAIL_DIR/skill/tests/trl/trl"
UNS="$DRAIL_DIR/skill/tests/unsloth/unsloth"

TOOLS="Read,Glob,Grep,Bash,Skill"

# 3 representative prompts covering key categories
PROMPTS=(
  # P1: Deep inheritance (hardest single-concept task)
  "In the directory $TF/, find the class PreTrainedModel and list all its base classes and mixins. Then pick one mixin and find where that mixin is defined."

  # P2: Cross-module tracing (requires multi-file search)
  "In the directory $UNS/, find the function select_attention_backend and where it is defined. Then find all model files that import run_attention. List each file and the function that uses it."

  # P3: Composite discovery (requires files + search + read)
  "In the directory $TF/models/llama4/, find all Python files, search for functions decorated with @auto_docstring, and show the function name and signature of each match."
)

PROMPT_NAMES=(
  "deep_inherit_tf"
  "cross_mod_trace"
  "composite_scan"
)

PROMPT_CATEGORIES=(
  "inheritance"
  "cross-module"
  "composite"
)

# Ground truth checkpoints
GROUND_TRUTH=(
  # P1: PreTrainedModel bases
  "PreTrainedModel is defined in modeling_utils.py|nn.Module is a base class|ModuleUtilsMixin is a base class|PushToHubMixin is a base class|PeftAdapterMixin is a base class|EmbeddingAccessMixin is a base class"

  # P2: select_attention_backend + run_attention
  "select_attention_backend is in utils/attention_dispatch.py|run_attention is found|At least 3 model files import run_attention|cohere.py or llama.py or gemma2.py imports run_attention|mistral.py or qwen3.py or falcon_h1.py imports run_attention"

  # P3: @auto_docstring in llama4
  "Found Python files in models/llama4/|modeling_llama4.py contains @auto_docstring|A forward method is decorated with @auto_docstring|At least 3 decorated functions/methods found|processing_llama4.py or image_processing_llama4.py also has @auto_docstring"
)

# ========================================================
# Metrics extraction
# ========================================================
extract_metrics() {
  local json_file="$1"
  local tool_calls bash_calls read_calls glob_calls grep_calls skill_calls turns
  local input_tokens output_tokens cache_read cache_create drail_used

  tool_calls=$(grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' "$json_file" 2>/dev/null | wc -l)
  bash_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Bash"' "$json_file" 2>/dev/null | wc -l)
  read_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Read"' "$json_file" 2>/dev/null | wc -l)
  glob_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Glob"' "$json_file" 2>/dev/null | wc -l)
  grep_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Grep"' "$json_file" 2>/dev/null | wc -l)
  skill_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Skill"' "$json_file" 2>/dev/null | wc -l)
  turns=$(grep -o '"type"[[:space:]]*:[[:space:]]*"assistant"' "$json_file" 2>/dev/null | wc -l)

  input_tokens=$(grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  output_tokens=$(grep -o '"output_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_read=$(grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_create=$(grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)

  drail_used=$(grep -o '"drail ' "$json_file" 2>/dev/null | wc -l)

  echo "${tool_calls:-0} ${input_tokens:-0} ${output_tokens:-0} ${cache_read:-0} ${cache_create:-0} ${turns:-0} ${bash_calls:-0} ${read_calls:-0} ${glob_calls:-0} ${grep_calls:-0} ${skill_calls:-0} ${drail_used:-0}"
}

# Extract text output from stream-json
extract_text_output() {
  local json_file="$1"
  python3 -c "
import json, sys
texts = []
for line in open('$json_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            msg = obj.get('message', {})
            for block in msg.get('content', []):
                if block.get('type') == 'text':
                    texts.append(block['text'])
        if obj.get('type') == 'result':
            texts.append(obj.get('result', ''))
    except: pass
print('\n'.join(texts))
" 2>/dev/null
}

# Also extract tool call details for analysis
extract_tool_details() {
  local json_file="$1"
  python3 -c "
import json
calls = []
for line in open('$json_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            msg = obj.get('message', {})
            for block in msg.get('content', []):
                if block.get('type') == 'tool_use':
                    name = block.get('name', '')
                    inp = block.get('input', {})
                    if name == 'Bash':
                        calls.append(f'Bash: {inp.get(\"command\", \"\")[:120]}')
                    elif name == 'Skill':
                        calls.append(f'Skill: {inp.get(\"skill\", \"\")} {inp.get(\"args\", \"\")}')
                    elif name == 'Read':
                        calls.append(f'Read: {inp.get(\"file_path\", \"\")[-60:]}')
                    elif name == 'Grep':
                        calls.append(f'Grep: {inp.get(\"pattern\", \"\")} in {inp.get(\"path\", \"\")[-40:]}')
                    elif name == 'Glob':
                        calls.append(f'Glob: {inp.get(\"pattern\", \"\")} in {inp.get(\"path\", \"\")[-40:]}')
                    else:
                        calls.append(f'{name}: ...')
    except: pass
for c in calls:
    print(c)
" 2>/dev/null
}

# Grade using opus as judge
grade_output() {
  local output_file="$1"
  local truth="$2"
  local prompt_name="$3"

  local output_text
  output_text=$(extract_text_output "$output_file" | head -c 4000)

  if [ -z "$output_text" ]; then
    echo "0.0 0 0 empty_output"
    return
  fi

  local grade
  grade=$(claude -p "You are a correctness grader. Score this output against the checkpoints.

CHECKPOINTS (pipe-separated, each is one fact to verify):
$truth

OUTPUT TO GRADE:
$output_text

For each checkpoint, check if the output contains that fact (exact names don't need to match perfectly, but the concept must be present).

Reply with ONLY a single JSON object, no other text:
{\"found\": <number of checkpoints satisfied>, \"total\": <total checkpoints>, \"score\": <found/total rounded to 2 decimals>, \"missed\": [\"brief description of each missed checkpoint\"]}
" --model haiku --output-format json --bare --allowedTools "" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result_text = data.get('result', '{}')
    r = json.loads(result_text)
    found = r.get('found', 0)
    total = r.get('total', 1)
    score = round(found / total * 5, 1)
    missed = '|'.join(r.get('missed', []))
    print(f'{score} {found} {total} {missed}')
except Exception as e:
    print(f'0.0 0 0 grading_error:{e}')
" 2>/dev/null)

  echo "${grade:-0.0 0 0 unknown}"
}

# ========================================================
# Main
# ========================================================
echo "============================================="
echo "  Quick Benchmark — $RUN_TAG"
echo "  $(date)"
echo "============================================="
echo "3 prompts, ${SKILL_ONLY:+skill-only}${SKILL_ONLY:-skill + no-skill}"
echo ""

# CSV header
CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,turns,bash,read,glob,grep,skill,drail_cmds,wall_seconds" > "$CSV"

SCORE_CSV="$RESULTS_DIR/scores.csv"
echo "prompt,mode,score,found,total,missed" > "$SCORE_CSV"

# ---- SKILL PHASE ----
echo "===== SKILL MODE ====="
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
cp -r "$SKILL_SRC/references" "$SKILL_DST/references" 2>/dev/null || true
echo "Skill installed to $SKILL_DST"

declare -a S_SCORES=()
total_skill_score=0

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"
  cat="${PROMPT_CATEGORIES[$i]}"

  echo -n "  [$((i+1))/3] $name ($cat) ... "
  out="$RESULTS_DIR/${name}_skill.jsonl"

  start=$(date +%s)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --allowedTools "$TOOLS" \
    > "$out" 2>/dev/null || true
  elapsed=$(( $(date +%s) - start ))

  read -r tc it ot cr cc tu ba re gl gr sk dr <<< "$(extract_metrics "$out")"
  echo "${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} S:${sk} drail:${dr}), ${tu} turns, ${elapsed}s"
  echo "$name,$cat,skill,$tc,$it,$ot,$tu,$ba,$re,$gl,$gr,$sk,$dr,$elapsed" >> "$CSV"

  # Save tool trace
  extract_tool_details "$out" > "$RESULTS_DIR/${name}_skill_tools.txt"

  # Grade
  echo -n "    Grading... "
  grade=$(grade_output "$out" "${GROUND_TRUTH[$i]}" "$name")
  score=$(echo "$grade" | awk '{print $1}')
  found=$(echo "$grade" | awk '{print $2}')
  total=$(echo "$grade" | awk '{print $3}')
  missed=$(echo "$grade" | cut -d' ' -f4-)
  S_SCORES+=("$score")
  total_skill_score=$(python3 -c "print(round($total_skill_score + $score, 1))")
  echo "$score/5 ($found/$total) missed: $missed"
  echo "$name,skill,$score,$found,$total,$missed" >> "$SCORE_CSV"
done

rm -rf "$SKILL_DST"
echo ""

# ---- NO-SKILL PHASE ----
declare -a N_SCORES=()
total_noskill_score=0

if [ "$SKILL_ONLY" = false ]; then
  echo "===== NO-SKILL MODE ====="
  for i in "${!PROMPTS[@]}"; do
    prompt="${PROMPTS[$i]}"
    name="${PROMPT_NAMES[$i]}"
    cat="${PROMPT_CATEGORIES[$i]}"

    echo -n "  [$((i+1))/3] $name ($cat) ... "
    out="$RESULTS_DIR/${name}_noskill.jsonl"

    start=$(date +%s)
    claude -p "$prompt" \
      --model sonnet \
      --output-format stream-json \
      --verbose \
      --permission-mode bypassPermissions \
      --disable-slash-commands \
      --allowedTools "$TOOLS" \
      > "$out" 2>/dev/null || true
    elapsed=$(( $(date +%s) - start ))

    read -r tc it ot cr cc tu ba re gl gr sk dr <<< "$(extract_metrics "$out")"
    echo "${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} S:${sk} drail:${dr}), ${tu} turns, ${elapsed}s"
    echo "$name,$cat,no-skill,$tc,$it,$ot,$tu,$ba,$re,$gl,$gr,$sk,$dr,$elapsed" >> "$CSV"

    extract_tool_details "$out" > "$RESULTS_DIR/${name}_noskill_tools.txt"

    echo -n "    Grading... "
    grade=$(grade_output "$out" "${GROUND_TRUTH[$i]}" "$name")
    score=$(echo "$grade" | awk '{print $1}')
    found=$(echo "$grade" | awk '{print $2}')
    total=$(echo "$grade" | awk '{print $3}')
    missed=$(echo "$grade" | cut -d' ' -f4-)
    N_SCORES+=("$score")
    total_noskill_score=$(python3 -c "print(round($total_noskill_score + $score, 1))")
    echo "$score/5 ($found/$total) missed: $missed"
    echo "$name,no-skill,$score,$found,$total,$missed" >> "$SCORE_CSV"
  done
fi

# ========================================================
# Summary
# ========================================================
echo ""
echo "============================================="
echo "  SUMMARY — $RUN_TAG"
echo "============================================="
echo ""
printf "%-20s | %8s" "Prompt" "Skill"
[ "$SKILL_ONLY" = false ] && printf " | %8s" "NoSkill"
echo ""
printf "%-20s-+-%8s" "--------------------" "--------"
[ "$SKILL_ONLY" = false ] && printf "-+-%8s" "--------"
echo ""
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-20s | %8s" "${PROMPT_NAMES[$i]}" "${S_SCORES[$i]:-0}"
  [ "$SKILL_ONLY" = false ] && printf " | %8s" "${N_SCORES[$i]:-0}"
  echo ""
done
printf "%-20s-+-%8s" "--------------------" "--------"
[ "$SKILL_ONLY" = false ] && printf "-+-%8s" "--------"
echo ""
printf "%-20s | %8s" "TOTAL (/15)" "$total_skill_score"
[ "$SKILL_ONLY" = false ] && printf " | %8s" "$total_noskill_score"
echo ""

# Write machine-readable summary
cat > "$RESULTS_DIR/summary.json" << EOFJ
{
  "run": "$RUN_TAG",
  "timestamp": "$(date -Iseconds)",
  "skill_scores": {
$(for i in "${!PROMPT_NAMES[@]}"; do
  comma=","
  [ "$i" -eq "$(( ${#PROMPT_NAMES[@]} - 1 ))" ] && comma=""
  echo "    \"${PROMPT_NAMES[$i]}\": ${S_SCORES[$i]:-0}${comma}"
done)
  },
  "skill_total": $total_skill_score,
  "noskill_total": ${total_noskill_score:-0},
  "prompts": ${#PROMPTS[@]}
}
EOFJ

echo ""
echo "CSV: $CSV"
echo "Scores: $SCORE_CSV"
echo "Summary: $RESULTS_DIR/summary.json"
echo "Tool traces: $RESULTS_DIR/*_tools.txt"
echo ""
echo "SKILL_TOTAL=$total_skill_score"
