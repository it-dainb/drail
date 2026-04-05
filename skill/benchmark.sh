#!/usr/bin/env bash
# Benchmark: drail skill — 6 challenging code navigation prompts
# Usage: benchmark.sh [--skill-only] [--parallel] [--run=N] [--release]

set +e

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
SKILL_SRC="$DRAIL_DIR/skill"
SKILL_DST="$HOME/.claude/skills/drail"
RUN_TAG="${RUN_TAG:-latest}"
SKILL_ONLY=false
PARALLEL=false
RELEASE=false

for arg in "$@"; do
  case "$arg" in
    --skill-only) SKILL_ONLY=true ;;
    --parallel) PARALLEL=true ;;
    --release) RELEASE=true; PARALLEL=true ;;
    --run=*) RUN_TAG="run${arg#*=}" ;;
  esac
done

# Release mode: read version, override output dir
if [ "$RELEASE" = true ]; then
  VERSION=$(grep '^version' "$DRAIL_DIR/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
  RESULTS_DIR="$DRAIL_DIR/skill/release/$VERSION"
  RUN_TAG="v$VERSION"
  SKILL_ONLY=false
else
  RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results/$RUN_TAG"
fi
mkdir -p "$RESULTS_DIR"

TF="$DRAIL_DIR/skill/tests/transformers/src/transformers"
TRL="$DRAIL_DIR/skill/tests/trl/trl"
UNS="$DRAIL_DIR/skill/tests/unsloth/unsloth"

TOOLS="Read,Glob,Grep,Bash,Skill"

# 6 Harder prompts
PROMPTS=(
  "In the directory $TRL/, find the _BaseTrainer class, then list ALL trainer classes that directly inherit from it. Include both stable trainers (in trainer/) and experimental trainers (in experimental/). Give the complete list with file paths."
  "In the file $TF/trainer.py, find the save_model method and explain the complete save logic: what conditions determine whether it calls save_pretrained, and what gets saved besides the model (tokenizer? data collator? configuration?)."
  "In the directory $TRL/, trace the impact chain: start from _generate_and_score_completions, find its direct callers, then find who calls THOSE callers (3 hops total). How deep does the impact go?"
  "Compare how DPOTrainer and GRPOTrainer in $TRL/ handle their compute_loss methods. What are the key differences in their loss computation? Which one is larger/more complex?"
  "Compare how model registration works in $UNS/ vs how model auto-mapping works in $TF/. In Unsloth, find the registry system. In Transformers, find MODEL_MAPPING or AUTO_MODEL_MAPPING. Describe the architectural difference."
  "In $TF/, analyze the dependency graph of trainer.py: what files does it import locally, and which of those imported files are also imported by other top-level files? Identify the most 'central' dependency that trainer.py shares with other modules."
)

PROMPT_NAMES=(full_hierarchy save_model_deep three_hop_impact trainer_comparison cross_repo_pattern dep_graph_analysis)
PROMPT_CATEGORIES=(completeness deep-analysis multi-hop comparison cross-repo deps-analysis)

GROUND_TRUTH=(
  "_BaseTrainer inherits from Trainer in base_trainer.py|DPOTrainer inherits from _BaseTrainer in dpo_trainer.py|GRPOTrainer inherits from _BaseTrainer in grpo_trainer.py|SFTTrainer inherits from _BaseTrainer in sft_trainer.py|RewardTrainer inherits from _BaseTrainer in reward_trainer.py|RLOOTrainer inherits from _BaseTrainer in rloo_trainer.py|At least 5 experimental trainers listed (BCO, CPO, KTO, PPO, etc.)|Total count is at least 15 trainer classes"
  "save_model is defined around line 3745 in trainer.py|It calls save_pretrained on the model|It saves the processing_class (tokenizer) via save_pretrained|It saves the data_collator tokenizer if present|It checks if model is FSDP/DeepSpeed wrapped|It has logic for _internal_call parameter to control push_to_hub|Output directory defaults to self.args.output_dir if None"
  "_generate_and_score_completions is called within _prepare_inputs in grpo_trainer.py and rloo_trainer.py|_prepare_inputs is called from the training loop or evaluation loop|The call happens via self._generate_and_score_completions|At least 2 levels of callers identified|The impact chain reaches at least 3 hops from the original method"
  "DPOTrainer.compute_loss is found in dpo_trainer.py|GRPOTrainer.compute_loss is found in grpo_trainer.py|DPO loss involves reference model or implicit approach|GRPO loss involves advantages or group scores|One is identified as larger or more complex than the other|Both are in the _BaseTrainer hierarchy"
  "Unsloth uses register_model function in registry/registry.py|Unsloth has per-family registration files (_llama.py, _gemma.py etc)|Transformers has MODEL_MAPPING or auto model mapping mechanism|The auto-mapping in Transformers is in models/auto/ directory|Architectural difference: Unsloth uses explicit registration, Transformers uses config-to-model mapping"
  "trainer.py imports from __init__.py|trainer.py imports from configuration_utils.py|trainer.py imports from data/data_collator.py|trainer.py imports from integrations/|At least one shared dependency identified (a file imported by both trainer.py and another module)|Some analysis of which dependency is most central or widely shared"
)

# ========================================================
# Shared functions
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

# Aggregate tokens across all jsonl files for a mode
aggregate_tokens() {
  local mode="$1"
  python3 -c "
import json, glob, os
total_in = 0
total_out = 0
total_cache_read = 0
total_cache_create = 0
for f in sorted(glob.glob('$RESULTS_DIR/*_${mode}.jsonl')):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try:
            obj = json.loads(line)
            usage = obj.get('message', {}).get('usage', {}) if obj.get('type') == 'assistant' else {}
            if not usage:
                usage = obj.get('usage', {})
            total_in += usage.get('input_tokens', 0)
            total_out += usage.get('output_tokens', 0)
            total_cache_read += usage.get('cache_read_input_tokens', 0)
            total_cache_create += usage.get('cache_creation_input_tokens', 0)
        except: pass
print(f'{total_in} {total_out} {total_cache_read} {total_cache_create}')
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
# run_phase — supports parallel and sequential
# ========================================================
run_phase() {
  local mode="$1"
  local extra_flags="$2"
  local -n scores_ref="$3"
  local -n total_ref="$4"
  local -n wall_ref="$5"

  total_ref=0
  local phase_start
  phase_start=$(date +%s)

  if [ "$PARALLEL" = true ]; then
    local pids=() out_files=() start_times=()

    echo "  Launching ${#PROMPTS[@]} prompts in parallel..."
    for i in "${!PROMPTS[@]}"; do
      local prompt="${PROMPTS[$i]}"
      local name="${PROMPT_NAMES[$i]}"
      local out="$RESULTS_DIR/${name}_${mode}.jsonl"
      out_files+=("$out")
      start_times+=("$(date +%s)")

      claude -p "$prompt" \
        --model sonnet \
        --output-format stream-json \
        --verbose \
        --permission-mode bypassPermissions \
        $extra_flags \
        --allowedTools "$TOOLS" \
        > "$out" 2>/dev/null &
      pids+=($!)
      echo "    [$((i+1))/${#PROMPTS[@]}] $name — PID ${pids[-1]}"
    done

    echo "  Waiting for all prompts to complete..."
    for i in "${!pids[@]}"; do
      wait "${pids[$i]}" 2>/dev/null || true
      local elapsed=$(( $(date +%s) - ${start_times[$i]} ))
      local name="${PROMPT_NAMES[$i]}"
      local out="${out_files[$i]}"

      read -r tc it ot cr cc tu ba re gl gr sk dr <<< "$(extract_metrics "$out")"
      echo "  [$((i+1))/${#PROMPTS[@]}] $name done: ${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} S:${sk} drail:${dr}), ${tu} turns, ${elapsed}s"
      echo "$name,${PROMPT_CATEGORIES[$i]},$mode,$tc,$it,$ot,$tu,$ba,$re,$gl,$gr,$sk,$dr,$elapsed" >> "$CSV"
      extract_tool_details "$out" > "$RESULTS_DIR/${name}_${mode}_tools.txt"
    done

    echo "  Grading all prompts in parallel..."
    local grade_pids=() grade_files=()
    for i in "${!PROMPTS[@]}"; do
      local name="${PROMPT_NAMES[$i]}"
      local out="${out_files[$i]}"
      local grade_tmp="$RESULTS_DIR/.grade_${name}_${mode}.tmp"
      grade_files+=("$grade_tmp")
      (grade_output "$out" "${GROUND_TRUTH[$i]}" "$name" > "$grade_tmp") &
      grade_pids+=($!)
    done

    for i in "${!grade_pids[@]}"; do
      wait "${grade_pids[$i]}" 2>/dev/null || true
      local name="${PROMPT_NAMES[$i]}"
      local grade
      grade=$(cat "${grade_files[$i]}" 2>/dev/null)
      rm -f "${grade_files[$i]}"

      local score found total_ck missed
      score=$(echo "$grade" | awk '{print $1}')
      found=$(echo "$grade" | awk '{print $2}')
      total_ck=$(echo "$grade" | awk '{print $3}')
      missed=$(echo "$grade" | cut -d' ' -f4-)
      scores_ref+=("$score")
      total_ref=$(python3 -c "print(round($total_ref + $score, 1))")
      echo "    $name: $score/5 ($found/$total_ck) missed: $missed"
      echo "$name,$mode,$score,$found,$total_ck,$missed" >> "$SCORE_CSV"
    done

  else
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
  fi

  wall_ref=$(( $(date +%s) - phase_start ))
}

# ========================================================
# Main
# ========================================================
echo "============================================="
if [ "$RELEASE" = true ]; then
  echo "  RELEASE Benchmark — v$VERSION"
else
  echo "  Benchmark — $RUN_TAG"
fi
echo "  $(date)"
[ "$PARALLEL" = true ] && echo "  Mode: PARALLEL" || echo "  Mode: Sequential"
echo "============================================="
echo "6 prompts"
echo ""

CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,turns,bash,read,glob,grep,skill,drail_cmds,wall_seconds" > "$CSV"

SCORE_CSV="$RESULTS_DIR/scores.csv"
echo "prompt,mode,score,found,total,missed" > "$SCORE_CSV"

# ---- NO-SKILL PHASE (first in release mode) ----
declare -a N_SCORES=()
total_noskill_score=0
noskill_wall=0

if [ "$SKILL_ONLY" = false ]; then
  echo "===== NO-SKILL MODE ====="
  rm -rf "$SKILL_DST" 2>/dev/null
  run_phase "no-skill" "--disable-slash-commands" N_SCORES total_noskill_score noskill_wall
  echo "  Wall time: ${noskill_wall}s"
  echo ""
fi

# ---- SKILL PHASE ----
echo "===== SKILL MODE ====="
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
cp -r "$SKILL_SRC/references" "$SKILL_DST/references" 2>/dev/null || true
echo "Skill installed."

declare -a S_SCORES=()
total_skill_score=0
skill_wall=0
run_phase "skill" "" S_SCORES total_skill_score skill_wall
echo "  Wall time: ${skill_wall}s"

rm -rf "$SKILL_DST"
echo ""

# ========================================================
# Aggregate token stats
# ========================================================
read -r skill_in skill_out skill_cr skill_cc <<< "$(aggregate_tokens "skill")"
if [ "$SKILL_ONLY" = false ]; then
  read -r noskill_in noskill_out noskill_cr noskill_cc <<< "$(aggregate_tokens "no-skill")"
else
  noskill_in=0; noskill_out=0; noskill_cr=0; noskill_cc=0
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
[ "$SKILL_ONLY" = false ] && printf -- "-+-%8s" "--------"
echo ""
for i in "${!PROMPT_NAMES[@]}"; do
  printf "%-24s | %8s" "${PROMPT_NAMES[$i]}" "${S_SCORES[$i]:-0}"
  [ "$SKILL_ONLY" = false ] && printf " | %8s" "${N_SCORES[$i]:-0}"
  echo ""
done
printf "%-24s-+-%8s" "------------------------" "--------"
[ "$SKILL_ONLY" = false ] && printf -- "-+-%8s" "--------"
echo ""
printf "%-24s | %8s" "TOTAL (/30)" "$total_skill_score"
[ "$SKILL_ONLY" = false ] && printf " | %8s" "$total_noskill_score"
echo ""

if [ "$SKILL_ONLY" = false ]; then
  echo ""
  echo "Token usage:"
  printf "  %-12s  in: %10s  out: %10s  wall: %ss\n" "Skill" "$skill_in" "$skill_out" "$skill_wall"
  printf "  %-12s  in: %10s  out: %10s  wall: %ss\n" "NoSkill" "$noskill_in" "$noskill_out" "$noskill_wall"
fi

# ========================================================
# Write summary.json
# ========================================================
cat > "$RESULTS_DIR/summary.json" << EOFJ
{
  "run": "$RUN_TAG",
  "version": "${VERSION:-}",
  "timestamp": "$(date -Iseconds)",
  "release": $RELEASE,
  "skill_scores": {
$(for i in "${!PROMPT_NAMES[@]}"; do
  comma=","
  [ "$i" -eq "$(( ${#PROMPT_NAMES[@]} - 1 ))" ] && comma=""
  echo "    \"${PROMPT_NAMES[$i]}\": ${S_SCORES[$i]:-0}${comma}"
done)
  },
  "noskill_scores": {
$(for i in "${!PROMPT_NAMES[@]}"; do
  comma=","
  [ "$i" -eq "$(( ${#PROMPT_NAMES[@]} - 1 ))" ] && comma=""
  echo "    \"${PROMPT_NAMES[$i]}\": ${N_SCORES[$i]:-0}${comma}"
done)
  },
  "skill_total": $total_skill_score,
  "noskill_total": ${total_noskill_score:-0},
  "prompts": ${#PROMPTS[@]},
  "skill_tokens": {"input": ${skill_in:-0}, "output": ${skill_out:-0}},
  "noskill_tokens": {"input": ${noskill_in:-0}, "output": ${noskill_out:-0}},
  "skill_wall_seconds": ${skill_wall:-0},
  "noskill_wall_seconds": ${noskill_wall:-0},
  "prompt_names": [$(printf '"%s",' "${PROMPT_NAMES[@]}" | sed 's/,$//')]
}
EOFJ

echo ""
echo "Scores: $SCORE_CSV"
echo "Summary: $RESULTS_DIR/summary.json"
echo "Tool traces: $RESULTS_DIR/*_tools.txt"
echo ""
echo "SKILL_TOTAL=$total_skill_score"

# ========================================================
# Release: update README benchmark table
# ========================================================
if [ "$RELEASE" = true ]; then
  echo ""
  echo "Updating README.md benchmark table..."
  bash "$DRAIL_DIR/skill/update_readme_bench.sh"
  echo "Done. Release saved to: $RESULTS_DIR"
fi
