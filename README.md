# patch

**CLI-first code intelligence for AI agents.** patch gives agents a small, explicit command set for reading code, finding symbols, searching text, tracing callers, listing files, mapping a codebase, and checking file-level dependencies.

The product goal is simple: make code navigation transparent, predictable, and cheap enough that an agent can recover from a bad query without spiraling into tool thrash.

## Why patch exists

Generic shell tools force agents to compose too many steps:

- list files
- guess which file matters
- read too much
- grep again
- re-read a narrower slice

patch turns those loops into explicit commands with stable output contracts. The CLI is the product. There is no query-classification shorthand, no hidden mode switch, and no host/editor install flow to understand before using it.

## Command families

patch uses explicit subcommands only:

```bash
patch read <path>
patch symbol find <query>
patch symbol callers <query>
patch search text <query>
patch search regex <pattern>
patch files <pattern>
patch deps <path>
patch map
```

Every command supports:

- dense text output by default
- `--json` for a stable machine-readable envelope
- `--budget` to cap response size

Scope-aware commands also accept `--scope <dir>`.

## Quick start

```bash
cargo build

cargo run -- symbol find main --scope src
cargo run -- files "*.rs" --scope src
cargo run -- deps src/main.rs
cargo run -- map --scope src
```

## What each command is for

### `read`

Read a file in full, by line range, or by markdown heading.

```bash
cargo run -- read README.md --lines 1:20
cargo run -- read README.md --heading "## Command families"
```

Use `read` when you already know the path and need exact content.

### `symbol find`

Find symbol definitions and usages with explicit kind filtering.

```bash
cargo run -- symbol find main --scope src
cargo run -- symbol find render --scope src/output --kind definition
```

Use `symbol find` when the target is code structure, not just matching text.

### `symbol callers`

Find call sites plus second-hop impact.

```bash
cargo run -- symbol callers render --scope src/output
```

Use `symbol callers` before changing a symbol that may affect downstream code.

### `search text`

Search literal text in comments, strings, docs, and code.

```bash
cargo run -- search text "symbol callers" --scope src
```

Use `search text` for exact phrases, docs, TODOs, or log strings.

### `search regex`

Search with an explicit regex command instead of slash-delimited magic.

```bash
cargo run -- search regex "symbol\\s+callers" --scope src
```

Use `search regex` when the match pattern is genuinely regular-expression based.

### `files`

Find files by glob.

```bash
cargo run -- files "*.rs" --scope src
```

Use `files` to narrow the surface area before reading or searching.

### `deps`

Inspect what a file imports and what imports it.

```bash
cargo run -- deps src/main.rs
```

Use `deps` before moving, renaming, or heavily restructuring a file.

### `map`

Generate a compact structural map of a codebase.

```bash
cargo run -- map --scope src
```

Use `map` once when entering an unfamiliar repo, then switch to targeted commands.

## Output philosophy

patch is designed for agent recovery, not just happy-path demos.

### Text output

Text output is optimized for direct consumption in an agent loop:

1. summary header first
2. meta block second
3. evidence block third
4. next block fourth
5. diagnostics last

Empty `Next` and `Diagnostics` sections render as `(none)`.

Diagnostics are ordered by severity:

- errors
- warnings
- hints

That ordering is stable across commands so agents can read the useful evidence before deciding whether a recovery hint matters. Diagnostic entries remain human-readable, and text-mode errors use the same section structure on stderr.

### JSON output

JSON output uses a shared envelope across all commands:

```json
{
  "command": "symbol.find",
  "schema_version": 2,
  "ok": true,
  "data": {},
  "next": [],
  "diagnostics": []
}
```

Command-specific payloads live under `data`, which always includes `meta`. Shared recovery guidance lives under top-level `next` and `diagnostics`. See [`docs/cli-contract.md`](docs/cli-contract.md) for the exact contract.

## Diagnostics and recovery

patch does not silently reinterpret user intent.

- Wrong selector? Return an error diagnostic.
- No matches? Return a sparse recovery hint.
- Probably meant a different command? Return a high-confidence suggestion only.

The CLI prefers explicit nudges over clever fallback behavior because predictable failures are easier for agents to recover from than magical behavior that changes across releases.

Current output limits are intentionally strict:

- at most 2 warnings
- at most 1 hint
- invalid command inputs aim to produce exactly 1 error diagnostic

## Agent workflow recommendations

For an unfamiliar codebase:

1. `map --scope src`
2. `files "*.rs" --scope src`
3. `symbol find <target> --scope src`
4. `symbol callers <target> --scope src` before signature changes
5. `read <path>` only after you know the exact file or section you need

For a likely text match rather than a symbol:

1. `search text`
2. `search regex` only if the literal search is too broad

For change planning:

1. `deps <path>`
2. `symbol callers <symbol>`

## Installation

### Cargo

```bash
cargo install --path .
```

### Local installer

The repository ships a CLI-only installer that targets a user-local bin directory.

```bash
./install.sh --dry-run
./install.sh
```

The installer does not mutate editor settings, host configs, or external tool manifests.

## Build and test

```bash
cargo build --release
cargo test
cargo clippy -- -D warnings
cargo fmt --check
```

## Stability promises

patch aims to keep these surfaces stable:

- explicit subcommand names
- shared JSON envelope
- diagnostics schema
- text section ordering

What is intentionally *not* supported:

- legacy query-shorthand mode
- removed install hosts or editor-integration flows
- undocumented aliases or fuzzy flag spellings

## Maintainers and contributors

If you change command names, JSON shape, or diagnostic behavior, update:

- `README.md`
- `docs/cli-contract.md`
- relevant integration tests in `tests/`

## License

MIT
