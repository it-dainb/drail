#!/usr/bin/env bash
# Hard Benchmark: drail skill — 6 hard prompts for iterative improvement
#
# Usage:
#   ./benchmark_hard.sh              # Run 6 prompts, skill + no-skill
#   ./benchmark_hard.sh --skill-only # Skill mode only
#   RUN_TAG=run1 ./benchmark_hard.sh # Tag a specific run

set -uo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
SKILL_SRC="$DRAIL_DIR/skill"
SKILL_DST="$HOME/.claude/skills/drail"
RUN_TAG="${RUN_TAG:-latest}"
SKILL_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --skill-only) SKILL_ONLY=true ;;
    --run=*) RUN_TAG="run${arg#*=}" ;;
  esac
done

RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_hard/$RUN_TAG"
mkdir -p "$RESULTS_DIR"

TF="$DRAIL_DIR/skill/tests/transformers/src/transformers"
TRL="$DRAIL_DIR/skill/tests/trl/trl"
UNS="$DRAIL_DIR/skill/tests/unsloth/unsloth"

TOOLS="Read,Glob,Grep,Bash,Skill"

# 6 Hard prompts
PROMPTS=(
  # H1: Deep call chain in massive file (trainer.py ~4600 lines)
  "In the directory $TF/, trace the training loss call chain: start from the Trainer.train method, find which method it delegates to for the training loop, then trace down to compute_loss. List each method in the chain with its file and line number."

  # H2: Cross-trainer shared pattern (multi-file callers)
  "In the directory $TRL/, find where the method _generate_and_score_completions is defined and used. List ALL trainer classes (both stable and experimental) that implement or call this method, and the file each one is in."

  # H3: Abstract method hierarchy (judge system)
  "In the directory $TRL/, find all abstract judge base classes and their abstract judge method signatures. Explain the hierarchy: which classes inherit from which, and how their judge method signatures differ."

  # H4: Massive override sweep (540 implementations)
  "In the directory $TF/models/, find how many implementations of get_input_embeddings exist. List the first 8 model families (by directory name) that have this override and the return type annotation if any."

  # H5: Registry dependency chain (init -> fan-out)
  "In the directory $UNS/, trace how the model registry gets populated. Start from search_models, follow to register_models, and list all the per-family registration functions it calls and which files they are in."

  # H6: Nonexistent symbol (edge case — should report not found)
  "In the directory $UNS/, find the class FastMambaModel. Show its class definition and what file it is in."
)

PROMPT_NAMES=(
  "deep_call_chain"
  "cross_trainer_shared"
  "judge_hierarchy"
  "override_sweep"
  "registry_chain"
  "nonexistent_symbol"
)

PROMPT_CATEGORIES=(
  "call-chain"
  "cross-module"
  "hierarchy"
  "override-sweep"
  "deps-chain"
  "edge-case"
)

# Ground truth (pipe-separated checkpoints)
GROUND_TRUTH=(
  # H1: Deep call chain
  "_inner_training_loop is defined in trainer.py around line 1431|train method calls inner_training_loop via find_executable_batch_size|_inner_training_loop calls training_step around line 1734|training_step is defined around line 1867|training_step calls compute_loss around line 1906|compute_loss is defined around line 1938"

  # H2: Cross-trainer shared pattern
  "_generate_and_score_completions is defined in grpo_trainer.py|_generate_and_score_completions is defined in rloo_trainer.py|dppo_trainer.py has an implementation|gfpo_trainer.py has an implementation|sdpo_trainer.py has an implementation|At least 5 total files found with this method"

  # H3: Judge hierarchy
  "BaseJudge is defined with abstract judge method|BaseRankJudge is a separate ABC not inheriting BaseJudge|BasePairwiseJudge inherits from BaseJudge|BaseBinaryJudge inherits from BaseJudge|judge method signatures differ between BaseJudge and BaseRankJudge|All are in judges.py in experimental/judges/"

  # H4: Override sweep
  "get_input_embeddings has many implementations (hundreds)|aimv2 has this override|albert has this override|align or altclip has this override|At least 8 model families listed|Return type nn.Module or nn.Embedding mentioned for at least one"

  # H5: Registry chain
  "search_models is in registry/__init__.py|search_models calls register_models|register_models calls per-family functions|_register_llama_models or _register_gemma_models found|Registration functions are in separate files like _llama.py or _gemma.py|At least 4 per-family registration functions identified"

  # H6: Nonexistent symbol
  "FastMambaModel does not exist or was not found|Agent reports it could not find the class|No hallucinated file path or definition|Response acknowledges the symbol is missing"
)

# ========================================================
# Metrics + grading functions (shared with benchmark_quick.sh)
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

extract_text_output() {
  local json_file="$1"
  python3 -c "
import json
texts = []
for line in open('$json_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            for block in obj.get('message', {}).get('content', []):
                if block.get('type') == 'text':
                    texts.append(block['text'])
        if obj.get('type') == 'result':
            texts.append(obj.get('result', ''))
    except: pass
print('\n'.join(texts))
" 2>/dev/null
}

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
            for block in obj.get('message', {}).get('content', []):
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

grade_output() {
  local output_file="$1"
  local truth="$2"
  local prompt_name="$3"

  local output_text
  output_text=$(extract_text_output "$output_file" | head -c 6000)

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

For each checkpoint, check if the output contains that fact (exact names don't need to match perfectly, but the concept must be present). Be generous with line numbers (within 20 lines is fine).

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
echo "  Hard Benchmark — $RUN_TAG"
echo "  $(date)"
echo "============================================="
echo "6 hard prompts"
echo ""

CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,turns,bash,read,glob,grep,skill,drail_cmds,wall_seconds" > "$CSV"

SCORE_CSV="$RESULTS_DIR/scores.csv"
echo "prompt,mode,score,found,total,missed" > "$SCORE_CSV"

run_phase() {
  local mode="$1"       # "skill" or "no-skill"
  local extra_flags="$2" # extra claude flags
  local -n scores_ref="$3"
  local -n total_ref="$4"

  total_ref=0

  for i in "${!PROMPTS[@]}"; do
    prompt="${PROMPTS[$i]}"
    name="${PROMPT_NAMES[$i]}"
    cat="${PROMPT_CATEGORIES[$i]}"

    echo -n "  [$((i+1))/6] $name ($cat) ... "
    out="$RESULTS_DIR/${name}_${mode}.jsonl"

    start=$(date +%s)
    claude -p "$prompt" \
      --model sonnet \
      --output-format stream-json \
      --verbose \
      --permission-mode bypassPermissions \
      $extra_flags \
      --allowedTools "$TOOLS" \
      > "$out" 2>/dev/null || true
    elapsed=$(( $(date +%s) - start ))

    read -r tc it ot cr cc tu ba re gl gr sk dr <<< "$(extract_metrics "$out")"
    echo "${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} S:${sk} drail:${dr}), ${tu} turns, ${elapsed}s"
    echo "$name,$cat,$mode,$tc,$it,$ot,$tu,$ba,$re,$gl,$gr,$sk,$dr,$elapsed" >> "$CSV"

    extract_tool_details "$out" > "$RESULTS_DIR/${name}_${mode}_tools.txt"

    echo -n "    Grading... "
    grade=$(grade_output "$out" "${GROUND_TRUTH[$i]}" "$name")
    score=$(echo "$grade" | awk '{print $1}')
    found=$(echo "$grade" | awk '{print $2}')
    total_ck=$(echo "$grade" | awk '{print $3}')
    missed=$(echo "$grade" | cut -d' ' -f4-)
    scores_ref+=("$score")
    total_ref=$(python3 -c "print(round($total_ref + $score, 1))")
    echo "$score/5 ($found/$total_ck) missed: $missed"
    echo "$name,$mode,$score,$found,$total_ck,$missed" >> "$SCORE_CSV"
  done
}

# ---- SKILL PHASE ----
echo "===== SKILL MODE ====="
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
cp -r "$SKILL_SRC/references" "$SKILL_DST/references" 2>/dev/null || true
echo "Skill installed."

declare -a S_SCORES=()
total_skill_score=0
run_phase "skill" "" S_SCORES total_skill_score

rm -rf "$SKILL_DST"
echo ""

# ---- NO-SKILL PHASE ----
declare -a N_SCORES=()
total_noskill_score=0

if [ "$SKILL_ONLY" = false ]; then
  echo "===== NO-SKILL MODE ====="
  run_phase "no-skill" "--disable-slash-commands" N_SCORES total_noskill_score
  echo ""
fi

# ========================================================
# Summary
# ========================================================
echo ""
echo "============================================="
echo "  SUMMARY — $RUN_TAG"
echo "============================================="
echo ""
printf "%-24s | %8s" "Prompt" "Skill"
[ "$SKILL_ONLY" = false ] && printf " | %8s" "NoSkill"
echo ""
printf "%-24s-+-%8s" "------------------------" "--------"
[ "$SKILL_ONLY" = false ] && printf "-+-%8s" "--------"
echo ""
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-24s | %8s" "${PROMPT_NAMES[$i]}" "${S_SCORES[$i]:-0}"
  [ "$SKILL_ONLY" = false ] && printf " | %8s" "${N_SCORES[$i]:-0}"
  echo ""
done
printf "%-24s-+-%8s" "------------------------" "--------"
[ "$SKILL_ONLY" = false ] && printf "-+-%8s" "--------"
echo ""
printf "%-24s | %8s" "TOTAL (/30)" "$total_skill_score"
[ "$SKILL_ONLY" = false ] && printf " | %8s" "$total_noskill_score"
echo ""

# Machine-readable summary
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
echo "Scores: $SCORE_CSV"
echo "Summary: $RESULTS_DIR/summary.json"
echo "Tool traces: $RESULTS_DIR/*_tools.txt"
echo ""
echo "SKILL_TOTAL=$total_skill_score"
