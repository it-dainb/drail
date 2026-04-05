# drail output contract

## Text output (default)

Sections in strict order:
1. `# <command>` — summary header (e.g., `# symbol.find`)
2. `## Meta` — key-value metadata
3. `## Evidence` — actual results (YOUR ANSWER)
4. `## Next` — follow-up suggestions for recovery
5. `## Diagnostics` — errors, warnings, hints

Empty sections render as `(none)`. Errors go to stderr with non-zero exit.

Diagnostic ordering: errors > warnings > hints. At most 2 warnings, 1 hint per response.

---

## JSON output (`--json`)

Shared envelope (schema v2):
```json
{
  "command": "symbol.find",
  "schema_version": 2,
  "ok": true,
  "data": {
    "meta": {}
  },
  "next": [],
  "diagnostics": []
}
```

### Top-level fields (always present)
- `command`: stable ID (`read`, `symbol.find`, `symbol.callers`, `search.text`, `search.regex`, `files`, `deps`, `map`, `scan`)
- `schema_version`: always `2`
- `ok`: boolean success
- `data`: command-specific payload
- `data.meta`: always present, `{}` when empty
- `next`: always `[]` when empty
- `diagnostics`: always `[]` when empty

### next items
```json
{"kind": "suggestion", "message": "...", "command": "drail ...", "confidence": "high"}
```

### diagnostics items
```json
{"level": "hint|warning|error", "code": "no_file_matches", "message": "..."}
```

---

## Command-specific data payloads

| Command | Key fields in `data` |
|---|---|
| `read` | `content`, `path`, `selector`, `meta.selector_kind`, `meta.selector_display` |
| `symbol.find` | `matches` (definitions + usages with body) |
| `symbol.callers` | `callers`, `impact`, `meta.truncated` |
| `search.text` | `matches` |
| `search.regex` | `matches` |
| `files` | `files` (with token estimates) |
| `deps` | `uses_local`, `uses_external`, `used_by`, `meta.truncated` |
| `map` | `entries`, `meta.total_files`, `meta.total_tokens`, `meta.truncated` |
| `scan` | `scopes` (per-scope: files, matches, summaries) |

---

## Configuration

### `.drailignore`
- Place in `--scope` root directory
- One file per scope (no nesting, no merging, parent dirs not searched)
- `.gitignore` is NOT read
- Affects: `files`, `symbol`, `search`, `deps` traversal, `map`, `scan`
- Does NOT block: explicit `read` paths, explicit `deps` target paths

### Environment variables
| Variable | Effect | Default |
|---|---|---|
| `DRAIL_THREADS` | Rayon thread-pool size | half of available CPUs, clamped 2-6 |
| `PAGER` | Pager for TTY text output | `less` |
| `LINES` | Terminal height override | `24` |
