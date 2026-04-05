#!/usr/bin/env bash
# Harder Benchmark v2: drail skill — 6 prompts designed to be very challenging
# Tests: efficiency, completeness, multi-step reasoning, ambiguous tasks

set +e

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

RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_harder/$RUN_TAG"
mkdir -p "$RESULTS_DIR"

TF="$DRAIL_DIR/skill/tests/transformers/src/transformers"
TRL="$DRAIL_DIR/skill/tests/trl/trl"
UNS="$DRAIL_DIR/skill/tests/unsloth/unsloth"

TOOLS="Read,Glob,Grep,Bash,Skill"

# 6 Harder prompts
PROMPTS=(
  # V2-H1: Full _BaseTrainer hierarchy — requires finding 15+ subclasses across stable+experimental
  "In the directory $TRL/, find the _BaseTrainer class, then list ALL trainer classes that directly inherit from it. Include both stable trainers (in trainer/) and experimental trainers (in experimental/). Give the complete list with file paths."

  # V2-H2: Trainer.save_model deep analysis — requires reading a huge method + tracing save_pretrained calls
  "In the file $TF/trainer.py, find the save_model method and explain the complete save logic: what conditions determine whether it calls save_pretrained, and what gets saved besides the model (tokenizer? data collator? configuration?)."

  # V2-H3: 3-hop impact trace — requires callers of callers
  "In the directory $TRL/, trace the impact chain: start from _generate_and_score_completions, find its direct callers, then find who calls THOSE callers (3 hops total). How deep does the impact go?"

  # V2-H4: Ambiguous multi-file structural comparison
  "Compare how DPOTrainer and GRPOTrainer in $TRL/ handle their compute_loss methods. What are the key differences in their loss computation? Which one is larger/more complex?"

  # V2-H5: Cross-repo pattern — find common patterns across 2 repos
  "Compare how model registration works in $UNS/ vs how model auto-mapping works in $TF/. In Unsloth, find the registry system. In Transformers, find MODEL_MAPPING or AUTO_MODEL_MAPPING. Describe the architectural difference."

  # V2-H6: deps + reverse deps chain — blast radius analysis
  "In $TF/, analyze the dependency graph of trainer.py: what files does it import locally, and which of those imported files are also imported by other top-level files? Identify the most 'central' dependency that trainer.py shares with other modules."
)

PROMPT_NAMES=(
  "full_hierarchy"
  "save_model_deep"
  "three_hop_impact"
  "trainer_comparison"
  "cross_repo_pattern"
  "dep_graph_analysis"
)

PROMPT_CATEGORIES=(
  "completeness"
  "deep-analysis"
  "multi-hop"
  "comparison"
  "cross-repo"
  "deps-analysis"
)

# Ground truth checkpoints
GROUND_TRUTH=(
  # V2-H1: Full _BaseTrainer hierarchy (15+ subclasses)
  "_BaseTrainer inherits from Trainer in base_trainer.py|DPOTrainer inherits from _BaseTrainer in dpo_trainer.py|GRPOTrainer inherits from _BaseTrainer in grpo_trainer.py|SFTTrainer inherits from _BaseTrainer in sft_trainer.py|RewardTrainer inherits from _BaseTrainer in reward_trainer.py|RLOOTrainer inherits from _BaseTrainer in rloo_trainer.py|At least 5 experimental trainers listed (BCO, CPO, KTO, PPO, etc.)|Total count is at least 15 trainer classes"

  # V2-H2: save_model deep analysis
  "save_model is defined around line 3745 in trainer.py|It calls save_pretrained on the model|It saves the processing_class (tokenizer) via save_pretrained|It saves the data_collator tokenizer if present|It checks if model is FSDP/DeepSpeed wrapped|It has logic for _internal_call parameter to control push_to_hub|Output directory defaults to self.args.output_dir if None"

  # V2-H3: 3-hop impact trace — requires callers of callers
  "_generate_and_score_completions is called within _prepare_inputs in grpo_trainer.py and rloo_trainer.py|_prepare_inputs is called from the training loop or evaluation loop|The call happens via self._generate_and_score_completions|At least 2 levels of callers identified|The impact chain reaches at least 3 hops from the original method"

  # V2-H4: DPO vs GRPO compute_loss comparison
  "DPOTrainer.compute_loss is found in dpo_trainer.py|GRPOTrainer.compute_loss is found in grpo_trainer.py|DPO loss involves reference model or implicit approach|GRPO loss involves advantages or group scores|One is identified as larger or more complex than the other|Both are in the _BaseTrainer hierarchy"

  # V2-H5: Cross-repo registration patterns
  "Unsloth uses register_model function in registry/registry.py|Unsloth has per-family registration files (_llama.py, _gemma.py etc)|Transformers has MODEL_MAPPING or auto model mapping mechanism|The auto-mapping in Transformers is in models/auto/ directory|Architectural difference: Unsloth uses explicit registration, Transformers uses config-to-model mapping"

  # V2-H6: trainer.py dependency graph
  "trainer.py imports from __init__.py|trainer.py imports from configuration_utils.py|trainer.py imports from data/data_collator.py|trainer.py imports from integrations/|At least one shared dependency identified (a file imported by both trainer.py and another module)|Some analysis of which dependency is most central or widely shared"
)

# ========================================================
# Shared functions (same as benchmark_hard.sh)
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
  output_text=$(extract_text_output "$output_file" | head -c 8000)

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

For each checkpoint, check if the output contains that fact (exact names don't need to match perfectly, but the concept must be present). Be generous with line numbers (within 50 lines is fine). For counts, accept approximate counts (e.g., 'at least 15' is satisfied by listing 12+).

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
echo "  Harder Benchmark v2 — $RUN_TAG"
echo "  $(date)"
echo "============================================="
echo "6 harder prompts"
echo ""

CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,turns,bash,read,glob,grep,skill,drail_cmds,wall_seconds" > "$CSV"

SCORE_CSV="$RESULTS_DIR/scores.csv"
echo "prompt,mode,score,found,total,missed" > "$SCORE_CSV"

run_phase() {
  local mode="$1"
  local extra_flags="$2"
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
