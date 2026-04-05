<p align="center">
  <h1 align="center">drail</h1>
  <p align="center"><strong>CLI-first code intelligence for AI agents</strong></p>
  <p align="center">
    <a href="#quick-start">Quick Start</a> &middot;
    <a href="#commands">Commands</a> &middot;
    <a href="#benchmarks">Benchmarks</a> &middot;
    <a href="#installation">Installation</a>
  </p>
</p>

---

drail gives AI agents a small, explicit command set for reading code, finding symbols, searching text, tracing callers, listing files, mapping codebases, and checking file-level dependencies.

One drail call replaces 3-6 Read/Grep/Glob cycles. Agents navigate code faster, use fewer tokens, and recover from bad queries without spiraling into tool thrash.

## Why drail

Generic shell tools force agents into multi-step loops: list files, guess which matters, read too much, grep again, re-read a narrower slice. Each step costs tokens and risks context drift.

drail turns those loops into **single commands** with stable output contracts:

| Without drail | With drail |
|---|---|
| `grep -rn "MyClass" src/` | `drail symbol find MyClass --scope src/` |
| `find . -name "*.py"` + `cat` each | `drail files "*.py" --scope src/` |
| `grep` + `Read` + `grep` + `Read` | `drail scan --scope src/ --pattern "X" --read-matching` |
| Manual caller tracing | `drail symbol callers fn_name --scope src/` |
| Multiple reads for hierarchy | `drail symbol find Class --scope src/ --parents` |

## Benchmarks

We test drail on 6 challenging code navigation tasks against real ML codebases (HuggingFace Transformers, TRL, Unsloth). Each task is scored 0-5 by an automated grader.

<!-- BENCH_TABLE_START -->
| Version | Mode | Hierarchy | Deep Analysis | Multi-hop | Comparison | Cross-repo | Deps | **Total** | Tokens (in/out) | Time |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.0.7 | No Skill | 4.4 | 4.3 | 4.0 | 4.2 | 5.0 | 5.0 | **26.9** | 2.5M / 13K | 1m 44s |
| | **With drail** | 5.0 | 5.0 | 5.0 | 4.2 | 5.0 | 4.2 | **28.4** | 3.7M / 17K | 2m 2s |
<!-- BENCH_TABLE_END -->

> Run `bash skill/benchmark.sh --release --parallel` to generate a new release benchmark.

## Quick Start

```bash
# Install
cargo install --path .

# Explore a codebase
drail map --scope src/
drail symbol find main --scope src/
drail files "*.rs" --scope src/
drail deps src/main.rs
```

## Commands

| Command | Purpose | Example |
|---|---|---|
| `read <path>` | Read files, line ranges, headings, JSON keys | `drail read src/main.rs --lines 10:50` |
| `symbol find <q>` | Find definitions + usages with inline bodies | `drail symbol find MyClass --scope src/ --parents` |
| `symbol callers <q>` | Call sites + 2nd-hop impact analysis | `drail symbol callers handler --scope src/` |
| `search text <q>` | Literal text search | `drail search text "TODO" --scope src/` |
| `search regex <p>` | Regex pattern search | `drail search regex "fn\s+\w+" --scope src/` |
| `files <glob>` | Find files by pattern | `drail files "*.py" --scope src/` |
| `deps <path>` | Import/dependent analysis | `drail deps src/auth.ts` |
| `map` | Structural codebase overview | `drail map --scope src/ --depth 3` |
| `scan` | Composite: files + search + outlines | `drail scan --scope src/ --pattern "pub fn" --read-matching` |

### Global flags

All commands support:
- `--json` — stable machine-readable JSON envelope (schema v2)
- `--budget <bytes>` — cap response size, trims least-important data first
- `--limit <n>` — override default result caps
- `--scope <dir>` — directory to search within

### Output structure

Every command returns 4 sections: **Meta** (query info), **Evidence** (your answer), **Next** (recovery suggestions), **Diagnostics** (warnings/errors). Empty sections render as `(none)`.

<details>
<summary><b>Output example</b></summary>

```text
# symbol.find

## Meta
- definitions: 1
- query: main
- scope: /path/to/src

## Evidence
symbol find "main" in /path/to/src — 2 matches

- main.rs:5-15 [definition]
  fn main() {

## Next
(none)

## Diagnostics
(none)
```
</details>

### Special features

- **`--parents`** — trace class/type inheritance hierarchy (shows `Parents:` and `Hierarchy:` chains)
- **JSON navigation** — `drail read data.json --key users.0.name` for dot-path access, `--index 0:3` for array slicing
- **Composite scanning** — `drail scan --scope src --scope tests --files "*.rs" --pattern "TODO" --read-matching` replaces chained files + search + read
- **`.drailignore`** — scope-root ignore file for traversal filtering (explicit paths bypass it)

## Installation

### From source (Cargo)

```bash
cargo install --path .
```

### Local installer

```bash
./install.sh          # install to ~/.local/bin
./install.sh --dry-run  # preview only
```

### npm

```bash
npm install -g drail-cli
```

## Claude Code Skill

drail ships with a [Claude Code skill](skill/SKILL.md) that teaches AI agents to use drail for all code navigation tasks. Install it to get AST-aware, token-efficient code exploration out of the box.

## Build & Test

```bash
cargo build --release
cargo test
cargo clippy -- -D warnings
cargo fmt --check
```

Pre-commit hook: `git config core.hooksPath .githooks`

## Stability

Stable surfaces: subcommand names, JSON envelope schema, diagnostics schema, text section ordering.

Not supported: legacy query shorthands, editor integrations, undocumented aliases.

## License

MIT
