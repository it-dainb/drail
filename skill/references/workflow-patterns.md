## Large file navigation
```bash
drail read src/server.rs                    # -> outline: [105-180] fn start()
drail read src/server.rs --lines 105:180   # -> the function you need
```

## JSON config navigation
```bash
drail read config.json --key database.host
drail read config.json --key users --index 0:3
drail read package.json --key scripts
```

## Handling truncated results
When `## Next` says results were truncated (e.g. "31 more matches not shown"):
```bash
drail search text "pattern" --scope src/ --limit 50   # override default cap of 10
drail symbol find TypeName --scope src/ --limit 30     # override default cap of 10
drail files "*.rs" --scope src/ --limit 50             # override default cap of 20
```
**Always re-run with `--limit` when completeness matters.** The `## Next` section provides the exact command.

## Trace a call chain
```bash
drail symbol callers target_symbol --scope src/
# callers = hop 1, impact = hop 2
# For deeper hops, chain another callers query:
drail symbol callers intermediate_symbol --scope src/
```
**Key:** If structural callers miss a relation, use `search text` for the concrete invocation text and confirm by reading the enclosing symbol.

## Multi-hop impact tracing
```bash
drail symbol callers target_symbol --scope src/
drail search text "target_symbol(" --scope src/   # fallback if structural callers miss
drail symbol callers direct_caller --scope src/
drail symbol callers hop2_caller --scope src/
```
For each hop, state: what calls what, the **exact call form** (e.g. `self.method_name()`, direct call, callback), file location, and hop depth.
When the prompt asks how far impact goes, answer with the deepest verified hop count, not a guess.
Always use `drail` commands for every step — never fall back to Read or Grep.

## Find complete implementation sets
```bash
drail symbol find target_symbol --scope src/
# Use when you need definitions with bodies inline.
# For exhaustive literal matches, use: drail search text "target_symbol" --scope src/ --limit 50
```
**Key:** `symbol find` gives structural results with bodies; `search text --limit` gives all literal occurrences.

## Trace type hierarchy
```bash
drail symbol find TypeName --scope src/ --kind definition
drail symbol find BaseType --scope src/ --kind definition   # if needed
```

## Find all derived types
```bash
drail symbol find BaseType --scope src/
# Definition shows parents; usages show derived types / implementations.
# If results are truncated, re-run with --limit to get full set.
```
**Answer format:**
1. State what the target type **inherits from / extends / implements** — trace the full chain (e.g. if BaseType extends GrandparentType, state both levels). Use `drail symbol find` on the parent to discover its parents.
2. List all derived types found
3. Give the total count
4. State scope coverage (e.g. "covers both stable/ and experimental/")

## Compare analogous implementations
```bash
drail symbol find TypeA --scope src/
drail symbol find TypeB --scope src/
drail symbol find method_name --scope src/
```
**Answer format:**
1. First line: state whether TypeA and TypeB share a common base type / interface / trait
2. Then: key inputs/signals each uses, structural differences, and relative complexity

## Dependency blast-radius check
```bash
drail deps src/auth.ts
# Shows uses_local, uses_external, and used_by.
```

## Read full symbol behavior
```bash
drail symbol find target_symbol --scope src/
# Then read the full body or signature if needed.
```
Capture side effects, important branches, and default/fallback behavior.

## Multi-scope scanning
```bash
drail scan --scope src --scope tests --pattern "TODO|FIXME" --budget 3000
```

## Cross-repo architecture comparison
```bash
drail search text "register|mapping|factory|dispatch" --scope projectA/
drail files "*.{rs,py,ts,js,go,java,cpp}" --scope projectA/
drail search text "register|mapping|factory|dispatch" --scope projectB/
```
State each codebase's extension mechanism, where it is defined, and the architectural difference in concrete terms — name specific structural patterns (e.g. per-variant registration files, centralized mapping dicts, factory classes).

## Find files and check structure
```bash
drail files "*.test.*" --scope src
drail read src/auth.test.ts
```

## Diagnostic-driven recovery
Prefer `## Next` suggestions from drail output over inventing recovery steps.
