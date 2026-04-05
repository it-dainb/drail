# drail commands — full reference

## Global flags

| Flag | Effect | Available on |
|---|---|---|
| `--json` | JSON envelope output (schema v2) | All commands |
| `--budget <bytes>` | Cap response size | All commands |

## read

Read a file in full, by line range, by markdown heading, or by JSON selector.

```bash
drail read README.md                                    # smart: full if small, outline if large
drail read README.md --lines 7:17                       # line range (1-based, inclusive)
drail read README.md --heading "## Command families"    # markdown section by heading text
drail read README.md --full                             # force full content (skip outline)
drail read data.json --key users.0.accounts             # JSON dot-path subtree
drail read data.json --index 0:3                        # JSON array slice (0-based, end-exclusive)
drail read data.json --key users --index 0:1            # dot-path + array slice combined
```

Selectors are mutually exclusive: `--full` | `--lines` | `--heading` | `--key` [+ `--index`] | `--index`.
`--key`/`--index` are JSON-only. `--lines` validation: START >= 1, END >= START.

Small files -> full content. Large files -> outline with line ranges (drill with `--lines`).
Minified files -> bounded preview (`minified_fallback_used`); explicit selectors bypass this.

---

## symbol find

Find symbol definitions and usages (AST-aware). Flags: `--scope <dir>` (default `.`), `--kind definition|usage`, `--budget`.

```bash
drail symbol find main --scope src
drail symbol find render --scope src/output --kind definition
```

Returns definitions with full body inline — no need to re-read. Falls back to text matching (`text_fallback_used`) when structural parsing fails. Recovery: Next suggests `search text`.

---

## symbol callers

Call sites + second-hop impact. Flags: `--scope <dir>` (default `.`), `--budget` (trims impact first, then callers).

```bash
drail symbol callers render --scope src/output
```

Returns `callers` + `impact`. Warns `callers_relation_not_meaningful` if query isn't callable (Next -> `symbol find`). Budget marks `truncated`.

---

## search text / search regex

```bash
drail search text "handleAuth" --scope src         # literal search
drail search regex "fn\s+\w+_handler" --scope src  # regex search
```

Flags: `--scope <dir>` (default `.`), `--budget`. Text: if query looks like `/pattern/`, Next suggests regex. Regex: invalid pattern -> `invalid_query` error.

---

## files

```bash
drail files "*.rs" --scope src
```

Glob match on filename or relative path. Returns token counts. Max 20 files. 0 matches -> suggests broader glob or lists extensions.

---

## deps

```bash
drail deps src/auth.ts --scope src
```

Returns: `uses_local` (project imports), `uses_external` (package imports), `used_by` (reverse dependents).
Max 25 exported symbols, 15 dependents (`truncated` flag). Explicit target bypasses `.drailignore`; traversal respects it.

---

## map

```bash
drail map --scope src --depth 5 --budget 3000
```

Flags: `--scope` (default `.`), `--depth` (default 3), `--budget`. Code files show symbols; non-code show token counts.

---

## scan

Composite command: file discovery + pattern search + structural outlines in one call.

```bash
drail scan --scope src/commands --files "*.rs"
drail scan --scope src --files "*.rs" --pattern "pub fn run" --read-matching
drail scan --scope src --scope tests --pattern "TODO|FIXME" --budget 4000
drail scan --scope src --files "*.py" --pattern "@auto_docstring" --read-matching --budget 2000
```

| Flag | Required | Repeatable | Effect |
|---|---|---|---|
| `--scope <dir>` | Yes | Yes | Directories to scan (1+) |
| `--files <glob>` | No | Yes | File pattern filter (OR-combined) |
| `--pattern <regex>` | No | Yes | Content pattern filter (OR-combined) |
| `--read-matching` | No | No | Generate structural outlines for matched files |
| `--budget <bytes>` | No | No | Cap output (trims: summaries > matches > files) |

**Power**: replaces chained `files` + `search` + `read` workflows. Multiple scopes, multiple globs, multiple patterns, all in one call.



Exit codes, diagnostic codes, `.drailignore`, and env vars: see `output-contract.md`.
