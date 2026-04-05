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
For each hop, **quote the exact source expression** as it appears in code (e.g. `self.target_symbol(args)`, `obj.method()`) with file and line number.
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
drail symbol find TypeName --scope src/ --kind definition --parents
# Shows Parents: inline + Hierarchy: chain (e.g. TypeName -> BaseType -> GrandparentType)
```

## Find all derived types
```bash
drail symbol find BaseType --scope src/ --parents
# Definition shows Parents: inline; usages show derived types / implementations.
# Hierarchy: section shows the full chain.
# If results are truncated, re-run with --limit to get full set.
```
**Answer format:**
1. **First line**: copy the `Hierarchy:` line from drail output verbatim (e.g. `Hierarchy: ChildType -> ParentType -> GrandparentType`)
2. State what the target type **inherits from / extends / implements** — report each ancestor and what IT inherits from (full chain)
3. List all derived types found
4. Give the total count
5. State scope coverage (e.g. "covers both stable/ and experimental/")

## Compare analogous implementations
```bash
drail symbol find TypeA --scope src/ --parents
drail symbol find TypeB --scope src/ --parents
drail symbol find method_name --scope src/
```
**Answer format:**
1. **First line**: "Both TypeA and TypeB inherit from Z" (or "TypeA and TypeB share no common base") — always state this even if not asked
2. Copy `Hierarchy:` lines from `--parents` output on each type
3. Then: key inputs/signals each uses, structural differences, and relative complexity

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
**Always name specific files** found in each codebase. State each codebase's extension mechanism, where it is defined (file path), and list concrete per-file or per-variant patterns (e.g. `_llama.py`, `_gemma.py`, `auto/modeling_auto.py`). The architectural comparison must cite file names, not just describe patterns abstractly.

## Find files and check structure
```bash
drail files "*.test.*" --scope src
drail read src/auth.test.ts
```

## Diagnostic-driven recovery
Prefer `## Next` suggestions from drail output over inventing recovery steps.
