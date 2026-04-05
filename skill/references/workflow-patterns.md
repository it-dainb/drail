# drail workflow patterns

## Large file navigation
```bash
drail read src/server.rs                    # -> outline: [105-180] fn start()
drail read src/server.rs --lines 105:180   # -> the function you need
```

## JSON config navigation
```bash
drail read config.json --key database.host           # -> just the host value
drail read config.json --key users --index 0:3       # -> first 3 users
drail read package.json --key scripts                # -> all npm scripts
```

## Trace a call chain (A calls B calls C)
```bash
# Use symbol callers — it already gives you 2 hops:
drail symbol callers compute_loss --scope src/
# The "callers" section = direct callers (hop 1)
# The "impact" section = who calls the callers (hop 2)
# This single command traces: compute_loss <- training_step <- _inner_training_loop

# For deeper hops, chain callers:
drail symbol callers training_step --scope src/
# Now you see training_step's callers and THEIR callers (hop 3-4)
```
**Key:** `symbol callers` includes a 2nd-hop `impact` section. Don't trace manually — read the impact field. For 3+ hops, chain another `symbol callers` call on the intermediate caller.

**Note:** `symbol callers` may return 0 results for `self.method()` calls (Python method calls with self prefix). In that case, use `search text "self.method_name("` or `symbol find method_name` to find call sites manually.

## Multi-hop impact tracing (3+ hops)
```bash
# Hop 1: Find direct callers of target method
drail symbol callers target_method --scope src/
# If 0 results (self.method call), fallback:
drail search text "self.target_method(" --scope src/
# Read the caller methods to confirm the call is via self.target_method(...)

# Hop 2: Find callers of the direct callers
drail symbol callers direct_caller --scope src/
# If 0 results, search text fallback again

# Hop 3: Find callers of hop-2 callers
drail symbol callers hop2_caller --scope src/
```
**Key:** For each hop, explicitly state:
1. **What calls what** — e.g., "method A calls self.B()" 
2. **The call mechanism** — e.g., "via self.method_name()" or "direct function call"
3. **Where** — file path and approximate line number
4. **Chain depth** — say hop 1 / hop 2 / hop 3 explicitly
Chain at least 3 hops when the prompt asks for deep impact. Don't stop at 2 hops.

**Example phrasing:** "`_prepare_inputs` calls `self._generate_and_score_completions(...)` in grpo_trainer.py; then `prediction_step` calls `_prepare_inputs(...)`; then the evaluation loop calls `prediction_step(...)`."
**If the prompt asks 'how deep does the impact go?'** answer with an explicit hop count, e.g. "verified 3 hops."

## Find ALL implementations/overrides of a method
```bash
# IMPORTANT: Use symbol find, NOT search text. search text caps at 10 results.
drail symbol find _generate_and_score_completions --scope src/
# Returns ALL definitions (even 7+) across stable and experimental code.
# symbol find --kind definition filters to definitions only.
```
**Key:** `search text` returns max 10 matches and may miss implementations. `symbol find` returns all definitions with full body inline. Always use `symbol find` when you need completeness.

## Find class and base classes
```bash
drail symbol find PreTrainedModel --scope src/ --kind definition
# Evidence shows class definition with all base classes/mixins inline. DONE.
```

## Trace inheritance chain
```bash
drail symbol find ClassName --scope src/ --kind definition
# Shows class + bases. Read the base:
drail symbol find BaseName --scope src/ --kind definition
# 2 commands. DONE.
```

## Find all subclasses
```bash
# Use symbol find WITHOUT --kind definition:
drail symbol find _BaseTrainer --scope src/
# Returns definition + ALL usages. Usages include every "class X(_BaseTrainer)" definition.
# This finds ALL subclasses across stable + experimental code.
# search text caps at 10 results and may miss subclasses.
# The definition shows what _BaseTrainer inherits from (its parent class).
```
**IMPORTANT:** When listing a class hierarchy, ALWAYS report:
1. What the target class **inherits from** (its base/parent class) — read the class definition line
2. ALL classes that **inherit from** the target (subclasses) — found in usages
3. The **final total count** of subclasses
4. Whether the list covers both **stable** and **experimental** locations when the prompt asks for both
Both directions matter. `symbol find X` gives you both: the definition shows parents, usages show children.

## Compare trainer loss implementations
```bash
# First establish hierarchy
drail symbol find DPOTrainer --scope src/
drail symbol find GRPOTrainer --scope src/
# Then inspect the loss methods
drail symbol find compute_loss --scope src/
```
**Always state upfront:**
1. `DPOTrainer` and `GRPOTrainer` both inherit from `_BaseTrainer`
2. DPO loss uses a reference-model / implicit-reference style comparison
3. GRPO loss uses advantages / group-normalized rewards or group scores
4. Then compare which implementation is larger/more complex


## Dependency blast-radius check
```bash
drail deps src/auth.ts
# Shows: what it imports (uses_local, uses_external) and who imports it (used_by)
# Before renaming/moving/deleting a file, check used_by is empty or manageable.
```

## Read full method behavior
```bash
drail symbol find save_model --scope src/
# Then read the method body or signature section.
```
**Always capture:**
1. What else gets saved besides the main model
2. Wrapper/distributed conditions
3. Default parameter behavior from the signature/body (e.g. `output_dir` falls back to `self.args.output_dir` when `None`)


## Multi-scope scanning
```bash
drail scan --scope src --scope tests --pattern "TODO|FIXME" --budget 3000
# Searches both src/ and tests/ for TODOs in one call.
```

## Cross-repo registration pattern comparison
```bash
# Unsloth side
drail search text "register_model" --scope unsloth/
drail files "*_*.py" --scope unsloth/models
# Transformers side
drail search text "MODEL_MAPPING" --scope transformers/models/auto
```
**Always state explicitly:**
1. Unsloth uses explicit registration via `register_model` in `registry/registry.py`
2. Unsloth has per-family files such as `_llama.py`, `_gemma.py`, etc.
3. Transformers uses config-to-model mappings in `models/auto/`
4. Architectural difference: Unsloth = explicit registration; Transformers = config-driven mapping


## Find files and check structure
```bash
drail files "*.test.*" --scope src
# Lists matching test files. Then drill into one:
drail read src/auth.test.ts
```

## Diagnostic-driven recovery
When drail returns 0 results, check `## Next`:
1. `no_symbol_matches` -> Next suggests `drail search text "..."` (try broader text search)
2. `no_search_matches` + slash-looking query -> Next suggests `drail search regex "..."`
3. `callers_relation_not_meaningful` -> symbol isn't callable, Next suggests `symbol find`
4. `no_file_matches` -> Next suggests broader glob or lists available extensions
5. `text_fallback_used` -> results are best-effort, structural parsing failed
6. `minified_fallback_used` -> file is minified, showing bounded preview

Always prefer the `## Next` suggestion over inventing your own recovery strategy.
