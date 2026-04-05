# drail — CLI-first code intelligence

A `drail` skill is installed on this system. **Load it** (e.g. `/drail` or trigger via keyword) for full AST-aware code navigation. The skill replaces Read, Grep, Glob, `grep`, `find`, and `cat` for all source-code tasks — it returns function bodies inline and replaces 3-6 tool cycles with a single call.

## Why use drail over built-in tools

| Built-in tool | Problem | drail replacement |
|---|---|---|
| Read tool / `cat` | No structure — dumps raw text | `drail read` — smart outline for large files, JSON navigation, heading selection |
| Grep tool / `grep` | Text-only, no AST awareness | `drail symbol find` — AST-aware, returns definition bodies inline |
| Glob tool / `find` | Just lists paths | `drail files` — lists with token counts; `drail scan` — files + search + outlines in one call |
| Multiple round-trips | 3-6 calls to find + read + search | `drail scan` / `drail symbol find` — single call covers the full workflow |

## Tool replacement table

| You want to...           | drail command                              | NOT these            |
|---|---|---|
| Read a file              | `drail read <path>`                        | Read tool, cat       |
| Read lines 100-200       | `drail read <path> --lines 100:200`        | Read tool with offset |
| Navigate JSON            | `drail read data.json --key users.0.name`  | Read + jq            |
| Find function/class/type | `drail symbol find X --scope <dir>`        | Grep tool, grep      |
| Who calls function X?    | `drail symbol callers X --scope <dir>`     | grep, Grep tool      |
| Literal text search      | `drail search text "Y" --scope <dir>`      | Grep tool, grep      |
| Regex search             | `drail search regex "pattern" --scope <dir>` | Grep tool, grep    |
| List files by glob       | `drail files "*.py" --scope <dir>`         | Glob tool, find      |
| File imports/dependents  | `drail deps <path>`                        | grep for imports     |
| Codebase structure       | `drail map --scope <dir>`                  | ls, Glob tool        |
| Composite scan           | `drail scan --scope <dir> --pattern "X"`   | Multiple tools       |

## Using the skill references

The drail skill includes reference files for deeper usage. Load them when needed:

- **`commands-reference.md`** — Full flag reference for every command (`read`, `symbol find`, `symbol callers`, `search text`, `search regex`, `files`, `deps`, `map`, `scan`). Consult when you need exact flag names, defaults, or edge-case behavior.
- **`workflow-patterns.md`** — Task-oriented recipes: large file navigation, call chain tracing, hierarchy exploration, multi-scope scanning, dependency blast-radius checks. Consult when tackling multi-step code exploration tasks.
- **`output-contract.md`** — Output format spec (text sections, JSON envelope schema v2, diagnostic codes, `.drailignore` rules, env vars). Consult when parsing drail output programmatically or debugging unexpected output.

## Quick examples

```bash
drail read src/auth.ts                              # read file (outline if large)
drail read config.json --key database.host           # navigate JSON
drail symbol find handleAuth --scope src/            # find definitions + usages
drail symbol callers render --scope src/             # call sites + 2nd-hop impact
drail search text "TODO" --scope src/                # literal search
drail search regex "fn\s+\w+_handler" --scope src/  # regex search
drail files "*.test.*" --scope src/                  # list files by glob
drail deps src/auth.ts                               # imports and dependents
drail map --scope src/                               # codebase overview
drail scan --scope src --pattern "pub fn" --read-matching  # composite scan
```

## Key rules

1. **Load the drail skill first** — invoke `/drail` or let keyword triggers auto-load it before any code navigation.
2. **drail is mandatory for source code** — never use Read, Grep, Glob, grep, find, or cat for source-code tasks.
3. **1-2 drail commands per task** — don't chain what one command covers.
4. **Body shown = done** — when `symbol find` returns a definition, the full body is already inline; don't re-read.
5. **Use `--budget`** to control large outputs rather than multiple narrow queries.
6. **Use `scan` for composite needs** — files + search + outlines in one call.
7. **Use `symbol callers` for impact tracing** — `impact` gives hop 2; chain another callers query for hop 3+.
8. **Follow `## Next` suggestions** — when results are empty or unexpected, run the suggested recovery command from drail output instead of guessing.

**Exceptions:** binary, image, and PDF files only — use other tools for those.
