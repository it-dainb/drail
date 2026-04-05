#!/usr/bin/env bash
# Benchmark V4: drail Skill vs Native Tools — Fair Hard Cases
#
# FAIR TEST RULES:
# - Zero mention of drail in any prompt or system prompt
# - Identical tools for both modes: Read, Glob, Grep, Bash
# - Identical prompts — purely task-oriented, tool-agnostic
# - With-skill: drail skill installed in ~/.claude/skills/drail/ (auto-discovered)
# - No-skill: skill removed, --disable-slash-commands to prevent any skill loading
# - Sequential runs (shared ~/.claude/skills/ prevents parallelism)

set -euo pipefail

DRAIL_DIR="/home/it-dainb/DATA/PROJECTS/drail"
SKILL_SRC="$DRAIL_DIR/skill"
SKILL_DST="$HOME/.claude/skills/drail"
RESULTS_DIR="$DRAIL_DIR/skill/benchmark_results_v4"
mkdir -p "$RESULTS_DIR"

# Test repo paths
TF="$DRAIL_DIR/skill/tests/transformers/src/transformers"
TRL="$DRAIL_DIR/skill/tests/trl/trl"
UNS="$DRAIL_DIR/skill/tests/unsloth/unsloth"

# Shared tools — both modes get everything
# Skill tool is required for skill activation (model calls Skill("drail") to load it)
TOOLS="Read,Glob,Grep,Bash,Skill"

# ========================================================
# 10 Hard-case prompts — ZERO mention of drail
# ========================================================
PROMPTS=(
  # P1: Deep inheritance — Transformers PreTrainedModel (4890-line file, 5 mixins)
  "In the directory $TF/, find the class PreTrainedModel and list all its base classes and mixins. Then pick one mixin and find where that mixin is defined."

  # P2: Deep inheritance — TRL BaseSelfDistillationTrainer (multi-mixin, experimental)
  "In the directory $TRL/, trace the inheritance chain of BaseSelfDistillationTrainer. What classes does it inherit from? Then find one concrete subclass that extends it."

  # P3: Cross-module fan-out — Transformers (500+ importers)
  "In the directory $TF/, find where the class PreTrainedModel is defined, then find 5 different files that import it. Show the import line from each file."

  # P4: Registry dispatch — Unsloth (registry system)
  "In the directory $UNS/, find the function register_model and trace which files call it. Then find one specific model registry file (like _llama.py or _gemma.py) and show what models it registers."

  # P5: Callback dispatch — Transformers (CallbackHandler event system)
  "In the directory $TF/, find the CallbackHandler class and explain how it dispatches events. Then find EarlyStoppingCallback and show which callback methods it overrides."

  # P6: Callback ecosystem — TRL (scattered callbacks)
  "In the directory $TRL/, find all classes that inherit from TrainerCallback. List each one, what file it is in, and which lifecycle methods (like on_step_end, on_train_begin) each one overrides."

  # P7: Large file navigation — Transformers GenerationMixin (3883 lines)
  "In the file $TF/generation/utils.py, find the class GenerationMixin and list all its public methods (methods not starting with underscore). How many public methods does it have?"

  # P8: Large file multi-class — Unsloth loader (1557 lines)
  "In the file $UNS/models/loader.py, find the FastLanguageModel class and its from_pretrained method. What parameters does it accept? Then find FastVisionModel in the same file and show its class definition."

  # P9: Composite discovery — Transformers (files + pattern + read)
  "In the directory $TF/models/llama4/, find all Python files, search for functions decorated with @auto_docstring, and show the function name and signature of each match."

  # P10: Cross-module utility tracing — Unsloth attention dispatch
  "In the directory $UNS/, find the function select_attention_backend and where it is defined. Then find all model files that import run_attention. List each file and the function that uses it."
)

PROMPT_NAMES=(
  "deep_inherit_tf"
  "deep_inherit_trl"
  "fanout_imports"
  "registry_dispatch"
  "callback_dispatch"
  "callback_ecosystem"
  "large_file_nav"
  "large_file_multi"
  "composite_scan"
  "cross_mod_trace"
)

PROMPT_CATEGORIES=(
  "inheritance"
  "inheritance"
  "cross-module"
  "registry"
  "callbacks"
  "callbacks"
  "large-file"
  "large-file"
  "composite"
  "cross-module"
)

# ========================================================
# Metrics extraction from stream-json
# ========================================================
extract_metrics() {
  local json_file="$1"

  local tool_calls bash_calls read_calls glob_calls grep_calls turns
  local input_tokens output_tokens cache_read cache_create

  tool_calls=$(grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' "$json_file" 2>/dev/null | wc -l)
  bash_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Bash"' "$json_file" 2>/dev/null | wc -l)
  read_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Read"' "$json_file" 2>/dev/null | wc -l)
  glob_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Glob"' "$json_file" 2>/dev/null | wc -l)
  grep_calls=$(grep -o '"name"[[:space:]]*:[[:space:]]*"Grep"' "$json_file" 2>/dev/null | wc -l)
  turns=$(grep -o '"type"[[:space:]]*:[[:space:]]*"assistant"' "$json_file" 2>/dev/null | wc -l)

  input_tokens=$(grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  output_tokens=$(grep -o '"output_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_read=$(grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)
  cache_create=$(grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$json_file" | grep -o '[0-9]*$' | tail -1)

  # Check if drail was used (look for "drail" in bash command args)
  local drail_used
  drail_used=$(grep -o '"drail ' "$json_file" 2>/dev/null | wc -l)

  echo "${tool_calls:-0} ${input_tokens:-0} ${output_tokens:-0} ${cache_read:-0} ${cache_create:-0} ${turns:-0} ${bash_calls:-0} ${read_calls:-0} ${glob_calls:-0} ${grep_calls:-0} ${drail_used:-0}"
}

# ========================================================
# Main
# ========================================================
echo "============================================="
echo "  Benchmark V4: Hard Cases — Fair Test"
echo "  $(date)"
echo "============================================="
echo ""
echo "10 prompts x 2 modes (sequential — shared skill dir)"
echo "  [skill]    = drail skill in ~/.claude/skills/drail/"
echo "  [no-skill] = no skill, --disable-slash-commands"
echo "  Both get tools: $TOOLS"
echo "  Zero drail mention in prompts or system prompts"
echo ""

# CSV header
CSV="$RESULTS_DIR/benchmark.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,cache_read,cache_create,turns,bash,read,glob,grep,drail_cmds,wall_seconds" > "$CSV"

# Accumulators
declare -a S_TC=() S_IT=() S_OT=() S_WL=() S_TU=() S_BA=() S_RE=() S_GL=() S_GR=() S_DR=()
declare -a N_TC=() N_IT=() N_OT=() N_WL=() N_TU=() N_BA=() N_RE=() N_GL=() N_GR=() N_DR=()

# --------------------------------------------------------
# PHASE 1: WITH-SKILL runs
# --------------------------------------------------------
echo "===== PHASE 1: WITH-SKILL ====="
echo "Installing skill to $SKILL_DST ..."
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
cp -r "$SKILL_SRC/references" "$SKILL_DST/references" 2>/dev/null || true
echo "Skill installed."
echo ""

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"
  cat="${PROMPT_CATEGORIES[$i]}"

  echo -n "  [$((i+1))/10] $name ($cat) ... "
  out="$RESULTS_DIR/${name}_skill.jsonl"

  start=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --allowedTools "$TOOLS" \
    > "$out" 2>/dev/null || true
  elapsed=$(( ( $(date +%s%N) - start ) / 1000000000 ))

  read -r tc it ot cr cc tu ba re gl gr dr <<< "$(extract_metrics "$out")"
  S_TC+=("$tc"); S_IT+=("$it"); S_OT+=("$ot"); S_WL+=("$elapsed"); S_TU+=("$tu")
  S_BA+=("$ba"); S_RE+=("$re"); S_GL+=("$gl"); S_GR+=("$gr"); S_DR+=("$dr")

  echo "${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} drail:${dr}), ${tu} turns, ${it}in+${ot}out, ${elapsed}s"
  echo "$name,$cat,skill,$tc,$it,$ot,$cr,$cc,$tu,$ba,$re,$gl,$gr,$dr,$elapsed" >> "$CSV"
done

# Remove skill before no-skill runs
echo ""
echo "Removing skill from $SKILL_DST ..."
rm -rf "$SKILL_DST"
echo "Skill removed."
echo ""

# --------------------------------------------------------
# PHASE 2: NO-SKILL runs
# --------------------------------------------------------
echo "===== PHASE 2: NO-SKILL ====="
echo ""

for i in "${!PROMPTS[@]}"; do
  prompt="${PROMPTS[$i]}"
  name="${PROMPT_NAMES[$i]}"
  cat="${PROMPT_CATEGORIES[$i]}"

  echo -n "  [$((i+1))/10] $name ($cat) ... "
  out="$RESULTS_DIR/${name}_noskill.jsonl"

  start=$(date +%s%N)
  claude -p "$prompt" \
    --model sonnet \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --disable-slash-commands \
    --allowedTools "$TOOLS" \
    > "$out" 2>/dev/null || true
  elapsed=$(( ( $(date +%s%N) - start ) / 1000000000 ))

  read -r tc it ot cr cc tu ba re gl gr dr <<< "$(extract_metrics "$out")"
  N_TC+=("$tc"); N_IT+=("$it"); N_OT+=("$ot"); N_WL+=("$elapsed"); N_TU+=("$tu")
  N_BA+=("$ba"); N_RE+=("$re"); N_GL+=("$gl"); N_GR+=("$gr"); N_DR+=("$dr")

  echo "${tc} tools (B:${ba} R:${re} G:${gl} P:${gr} drail:${dr}), ${tu} turns, ${it}in+${ot}out, ${elapsed}s"
  echo "$name,$cat,no-skill,$tc,$it,$ot,$cr,$cc,$tu,$ba,$re,$gl,$gr,$dr,$elapsed" >> "$CSV"
done

# ========================================================
# PHASE 3: CORRECTNESS GRADING (LLM-as-judge)
# ========================================================
echo ""
echo "===== PHASE 3: CORRECTNESS GRADING ====="
echo "Using opus as judge — scoring each output against ground truth"
echo ""

# Ground truth: required facts per prompt (pipe-separated checkpoints)
# Each checkpoint is a fact the output MUST contain to score a point.
# Score = (checkpoints found) / (total checkpoints) * 5, rounded.
GROUND_TRUTH=(
  # P1: PreTrainedModel bases
  "PreTrainedModel is defined in modeling_utils.py|nn.Module is a base class|ModuleUtilsMixin is a base class|PushToHubMixin is a base class|PeftAdapterMixin is a base class|EmbeddingAccessMixin is a base class"

  # P2: BaseSelfDistillationTrainer
  "BaseSelfDistillationTrainer is in base_self_distillation_trainer.py or experimental/self_distillation|OnlineRolloutMixin is a base class|SelfDistillationMixin is a base class|_BaseTrainer is a base class|SDPOTrainer or GOLDTrainer or GKDTrainer is a concrete subclass"

  # P3: PreTrainedModel importers
  "PreTrainedModel is defined in modeling_utils.py|Found at least 5 files that import it|trainer.py imports it|At least one file from models/ directory imports it|At least one file from pipelines/ or generation/ imports it"

  # P4: register_model in unsloth
  "register_model is in registry/registry.py|Found files that call register_model or _register_models|Found a specific model registry file like _llama.py or _gemma.py or _qwen.py|Shows what models are registered in that file"

  # P5: CallbackHandler dispatch
  "CallbackHandler is in trainer_callback.py|It inherits from TrainerCallback|It dispatches by iterating over callbacks or calling getattr|EarlyStoppingCallback is found|EarlyStoppingCallback overrides on_train_begin or on_evaluate"

  # P6: TRL TrainerCallback subclasses
  "SyncRefModelCallback in callbacks.py|RichProgressCallback in callbacks.py|LogCompletionsCallback in callbacks.py|At least one lifecycle method like on_step_end or on_train_begin identified|Found at least 4 callback classes total"

  # P7: GenerationMixin public methods
  "GenerationMixin is in generation/utils.py|generate method found|compute_transition_scores found|Identified at least 4 public methods|heal_tokens or prepare_inputs_for_generation found"

  # P8: FastLanguageModel in loader.py
  "FastLanguageModel is in models/loader.py|from_pretrained method found|model_name parameter identified|max_seq_length or dtype or load_in_4bit parameter found|FastVisionModel found in same file"

  # P9: @auto_docstring in llama4
  "Found Python files in models/llama4/|modeling_llama4.py contains @auto_docstring|A forward method is decorated with @auto_docstring|At least 3 decorated functions/methods found|processing_llama4.py or image_processing_llama4.py also has @auto_docstring"

  # P10: select_attention_backend + run_attention
  "select_attention_backend is in utils/attention_dispatch.py|run_attention is found|At least 3 model files import run_attention|cohere.py or llama.py or gemma2.py imports run_attention|mistral.py or qwen3.py or falcon_h1.py imports run_attention"
)

# Extract final text output from stream-json (all assistant text blocks)
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
    except: pass
# Also try result type
for line in open('$json_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result':
            texts.append(obj.get('result', ''))
    except: pass
print('\n'.join(texts))
" 2>/dev/null
}

grade_output() {
  local output_file="$1"
  local truth="$2"
  local prompt_name="$3"

  local output_text
  output_text=$(extract_text_output "$output_file")

  # If empty, also try extracting from tool results (the agent may have produced output via tools only)
  if [ -z "$output_text" ]; then
    output_text=$(python3 -c "
import json
texts = []
for line in open('$output_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'user':
            msg = obj.get('message', {})
            for block in msg.get('content', []):
                if isinstance(block, dict) and block.get('type') == 'tool_result':
                    texts.append(str(block.get('content', '')))
    except: pass
print('\n'.join(texts[-3:]))
" 2>/dev/null)
  fi

  # Truncate to ~4000 chars to fit haiku context
  output_text=$(echo "$output_text" | head -c 4000)

  # Use haiku as judge
  local grade
  grade=$(claude -p "You are a correctness grader. Score this output against the checkpoints.

CHECKPOINTS (pipe-separated, each is one fact to verify):
$truth

OUTPUT TO GRADE:
$output_text

For each checkpoint, check if the output contains that fact (exact names don't need to match perfectly, but the concept must be present).

Reply with ONLY a single JSON object, no other text:
{\"found\": <number of checkpoints satisfied>, \"total\": <total checkpoints>, \"score\": <found/total rounded to 2 decimals>, \"missed\": [\"brief description of each missed checkpoint\"]}
" --model opus --output-format json --bare --allowedTools "" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result_text = data.get('result', '{}')
    # Try to parse the result as JSON
    r = json.loads(result_text)
    found = r.get('found', 0)
    total = r.get('total', 1)
    score = round(found / total * 5, 1)
    missed = ', '.join(r.get('missed', []))
    print(f'{score} {found} {total} {missed}')
except Exception as e:
    print(f'0.0 0 0 grading_error: {e}')
" 2>/dev/null)

  echo "$grade"
}

# Grade all outputs
GRADE_CSV="$RESULTS_DIR/correctness.csv"
echo "prompt,mode,score_out_of_5,found,total,missed" > "$GRADE_CSV"

declare -a S_SCORES=() N_SCORES=()

for i in "${!PROMPT_NAMES[@]}"; do
  name="${PROMPT_NAMES[$i]}"
  truth="${GROUND_TRUTH[$i]}"

  # Grade skill output
  echo -n "  Grading $name [skill]... "
  skill_grade=$(grade_output "$RESULTS_DIR/${name}_skill.jsonl" "$truth" "$name")
  skill_score=$(echo "$skill_grade" | awk '{print $1}')
  skill_found=$(echo "$skill_grade" | awk '{print $2}')
  skill_total=$(echo "$skill_grade" | awk '{print $3}')
  skill_missed=$(echo "$skill_grade" | cut -d' ' -f4-)
  S_SCORES+=("${skill_score%.*}${skill_score#*.}")  # store as int*10 for averaging
  echo "$skill_score/5 ($skill_found/$skill_total)"
  echo "$name,skill,$skill_score,$skill_found,$skill_total,\"$skill_missed\"" >> "$GRADE_CSV"

  # Grade no-skill output
  echo -n "  Grading $name [no-skill]... "
  noskill_grade=$(grade_output "$RESULTS_DIR/${name}_noskill.jsonl" "$truth" "$name")
  noskill_score=$(echo "$noskill_grade" | awk '{print $1}')
  noskill_found=$(echo "$noskill_grade" | awk '{print $2}')
  noskill_total=$(echo "$noskill_grade" | awk '{print $3}')
  noskill_missed=$(echo "$noskill_grade" | cut -d' ' -f4-)
  N_SCORES+=("${noskill_score%.*}${noskill_score#*.}")
  echo "$noskill_score/5 ($noskill_found/$noskill_total)"
  echo "$name,no-skill,$noskill_score,$noskill_found,$noskill_total,\"$noskill_missed\"" >> "$GRADE_CSV"
done

# Also update CSV with scores
SCORE_CSV="$RESULTS_DIR/benchmark_with_scores.csv"
echo "prompt,category,mode,tool_calls,input_tokens,output_tokens,turns,wall_seconds,correctness" > "$SCORE_CSV"

# Re-read the main CSV and merge scores
idx_s=0
idx_n=0
while IFS=, read -r pname pcat pmode ptc pit pot pcr pcc ptu pba pre pgl pgr pdr pws; do
  [ "$pname" = "prompt" ] && continue  # skip header
  if [ "$pmode" = "skill" ]; then
    score="${S_SCORES[$idx_s]:-0}"
    # Convert back: e.g. "42" -> "4.2"
    score_fmt="${score:0:${#score}-1}.${score: -1}"
    [ ${#score} -eq 1 ] && score_fmt="0.$score"
    echo "$pname,$pcat,$pmode,$ptc,$pit,$pot,$ptu,$pws,$score_fmt" >> "$SCORE_CSV"
    idx_s=$((idx_s + 1))
  else
    score="${N_SCORES[$idx_n]:-0}"
    score_fmt="${score:0:${#score}-1}.${score: -1}"
    [ ${#score} -eq 1 ] && score_fmt="0.$score"
    echo "$pname,$pcat,$pmode,$ptc,$pit,$pot,$ptu,$pws,$score_fmt" >> "$SCORE_CSV"
    idx_n=$((idx_n + 1))
  fi
done < "$CSV"

echo ""
echo "Correctness CSV: $GRADE_CSV"
echo "Combined CSV: $SCORE_CSV"

# ========================================================
# SUMMARY
# ========================================================
echo ""
echo "============================================="
echo "  SUMMARY"
echo "============================================="

sum() { local s=0; for v in "$@"; do s=$((s + v)); done; echo $s; }
avg() { local s=0; local n=$#; for v in "$@"; do s=$((s + v)); done; echo $((s / n)); }
pct() { [ "$2" -gt 0 ] && echo "$(( ($2 - $1) * 100 / $2 ))%" || echo "N/A"; }

ts=$(sum "${S_TC[@]}");  tn=$(sum "${N_TC[@]}")
is=$(sum "${S_IT[@]}");  in_=$(sum "${N_IT[@]}")
os=$(sum "${S_OT[@]}");  on=$(sum "${N_OT[@]}")
ws=$(sum "${S_WL[@]}");  wn=$(sum "${N_WL[@]}")
us=$(sum "${S_TU[@]}");  un=$(sum "${N_TU[@]}")
bs=$(sum "${S_BA[@]}");  bn=$(sum "${N_BA[@]}")
rs=$(sum "${S_RE[@]}");  rn=$(sum "${N_RE[@]}")
gs=$(sum "${S_GL[@]}");  gn=$(sum "${N_GL[@]}")
ps=$(sum "${S_GR[@]}");  pn=$(sum "${N_GR[@]}")
ds=$(sum "${S_DR[@]}");  dn=$(sum "${N_DR[@]}")

printf "\n%-24s %12s %12s %10s %8s\n" "Metric" "Skill" "No Skill" "Delta" "Improv"
printf "%-24s %12s %12s %10s %8s\n" "------------------------" "------------" "------------" "----------" "--------"
printf "%-24s %12d %12d %+10d %8s\n" "Total tool calls"   "$ts" "$tn" "$((ts-tn))" "$(pct $ts $tn)"
printf "%-24s %12d %12d %+10d %8s\n" "  Bash"              "$bs" "$bn" "$((bs-bn))" ""
printf "%-24s %12d %12d %+10d %8s\n" "  Read"              "$rs" "$rn" "$((rs-rn))" ""
printf "%-24s %12d %12d %+10d %8s\n" "  Glob"              "$gs" "$gn" "$((gs-gn))" ""
printf "%-24s %12d %12d %+10d %8s\n" "  Grep"              "$ps" "$pn" "$((ps-pn))" ""
printf "%-24s %12d %12d %+10d %8s\n" "  drail cmds"        "$ds" "$dn" "$((ds-dn))" ""
printf "%-24s %12d %12d %+10d %8s\n" "Total turns"         "$us" "$un" "$((us-un))" "$(pct $us $un)"
printf "%-24s %12d %12d %+10d %8s\n" "Total input tokens"  "$is" "$in_" "$((is-in_))" "$(pct $is $in_)"
printf "%-24s %12d %12d %+10d %8s\n" "Total output tokens" "$os" "$on" "$((os-on))" "$(pct $os $on)"
printf "%-24s %12d %12d %+10d %8s\n" "Total wall time (s)" "$ws" "$wn" "$((ws-wn))" "$(pct $ws $wn)"
printf "%-24s %12d %12d %+10d\n"     "Avg tool calls"      "$(avg "${S_TC[@]}")" "$(avg "${N_TC[@]}")" "$(( $(avg "${S_TC[@]}") - $(avg "${N_TC[@]}") ))"
printf "%-24s %12d %12d %+10d\n"     "Avg wall time (s)"   "$(avg "${S_WL[@]}")" "$(avg "${N_WL[@]}")" "$(( $(avg "${S_WL[@]}") - $(avg "${N_WL[@]}") ))"

echo ""
echo "--- Per-prompt breakdown ---"
printf "%-20s %-12s | %5s %5s | %6s %6s | %5s %5s | %5s %5s | %5s %5s\n" \
  "Prompt" "Category" "Tools" "Tools" "Out" "Out" "Time" "Time" "Turns" "Turns" "Score" "Score"
printf "%-20s %-12s | %5s %5s | %6s %6s | %5s %5s | %5s %5s | %5s %5s\n" \
  "" "" "skill" "none" "skill" "none" "skill" "none" "skill" "none" "skill" "none"
printf "%-20s-%-12s-+-%5s-%5s-+-%6s-%6s-+-%5s-%5s-+-%5s-%5s-+-%5s-%5s\n" \
  "--------------------" "------------" "-----" "-----" "------" "------" "-----" "-----" "-----" "-----" "-----" "-----"
for i in "${!PROMPT_NAMES[@]}"; do
  # Convert stored int scores back to X.X format
  ss="${S_SCORES[$i]:-0}"
  ns="${N_SCORES[$i]:-0}"
  ss_fmt="${ss:0:${#ss}-1}.${ss: -1}"; [ ${#ss} -eq 1 ] && ss_fmt="0.$ss"
  ns_fmt="${ns:0:${#ns}-1}.${ns: -1}"; [ ${#ns} -eq 1 ] && ns_fmt="0.$ns"

  printf "%-20s %-12s | %5d %5d | %6d %6d | %5d %5d | %5d %5d | %5s %5s\n" \
    "${PROMPT_NAMES[$i]}" "${PROMPT_CATEGORIES[$i]}" \
    "${S_TC[$i]}" "${N_TC[$i]}" \
    "${S_OT[$i]}" "${N_OT[$i]}" \
    "${S_WL[$i]}" "${N_WL[$i]}" \
    "${S_TU[$i]}" "${N_TU[$i]}" \
    "$ss_fmt" "$ns_fmt"
done

echo ""
echo "--- Category averages ---"
declare -A CAT_S_TC CAT_N_TC CAT_S_OT CAT_N_OT CAT_S_WL CAT_N_WL CAT_CNT
for i in "${!PROMPT_NAMES[@]}"; do
  c="${PROMPT_CATEGORIES[$i]}"
  CAT_S_TC[$c]=$(( ${CAT_S_TC[$c]:-0} + ${S_TC[$i]} ))
  CAT_N_TC[$c]=$(( ${CAT_N_TC[$c]:-0} + ${N_TC[$i]} ))
  CAT_S_OT[$c]=$(( ${CAT_S_OT[$c]:-0} + ${S_OT[$i]} ))
  CAT_N_OT[$c]=$(( ${CAT_N_OT[$c]:-0} + ${N_OT[$i]} ))
  CAT_S_WL[$c]=$(( ${CAT_S_WL[$c]:-0} + ${S_WL[$i]} ))
  CAT_N_WL[$c]=$(( ${CAT_N_WL[$c]:-0} + ${N_WL[$i]} ))
  CAT_CNT[$c]=$(( ${CAT_CNT[$c]:-0} + 1 ))
done
printf "%-14s | %10s %10s | %10s %10s | %10s %10s\n" "Category" "Avg Tools" "Avg Tools" "Avg Out" "Avg Out" "Avg Time" "Avg Time"
printf "%-14s | %10s %10s | %10s %10s | %10s %10s\n" "" "skill" "none" "skill" "none" "skill" "none"
printf "%-14s-+-%10s-%10s-+-%10s-%10s-+-%10s-%10s\n" "--------------" "----------" "----------" "----------" "----------" "----------" "----------"
for c in "${!CAT_CNT[@]}"; do
  n=${CAT_CNT[$c]}
  printf "%-14s | %10d %10d | %10d %10d | %10d %10d\n" \
    "$c" \
    "$(( ${CAT_S_TC[$c]} / n ))" "$(( ${CAT_N_TC[$c]} / n ))" \
    "$(( ${CAT_S_OT[$c]} / n ))" "$(( ${CAT_N_OT[$c]} / n ))" \
    "$(( ${CAT_S_WL[$c]} / n ))" "$(( ${CAT_N_WL[$c]} / n ))"
done

echo ""
echo "Raw CSV: $CSV"
echo "Raw JSONL: $RESULTS_DIR/"
