# CLI contract

`patch` is a subcommand-only CLI for AI-agent-first code navigation. This document captures the public command surface and the output contract that the integration tests pin.

## Command families

The supported top-level commands are:

- `read`
- `symbol find`
- `symbol callers`
- `search text`
- `search regex`
- `files`
- `deps`
- `map`

There is no query-shorthand mode, no MCP runtime, and no editor/host install flow.

## Shared JSON envelope

Every command supports `--json` and returns the same top-level shape:

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

### Envelope fields

- `command`: stable command identifier such as `read`, `symbol.find`, or `search.regex`
- `schema_version`: currently `2`
- `ok`: boolean success flag
- `data`: command-specific payload object with always-present `meta`
- `next`: ordered list of high-confidence follow-up suggestions
- `diagnostics`: ordered list of recovery diagnostics

## Diagnostics contract

Diagnostics are shared across commands and use this shape:

```json
{
  "level": "hint",
  "code": "search.no_matches",
  "message": "No matches found.",
  "suggestion": "Try search text with a broader phrase."
}
```

- `level` is one of `error`, `warning`, or `hint`
- `code` is a stable machine-readable identifier
- `message` is a human-readable explanation
- `suggestion` is optional and appears only for high-confidence next steps

Current behavior stays intentionally sparse:

- invalid command inputs aim to produce exactly 1 error diagnostic
- successful commands emit at most 2 warnings
- successful commands emit at most 1 hint

## Text output ordering

Dense text output is designed for agent loops and follows a stable section order:

1. summary header
2. meta
3. evidence
4. next
5. diagnostics

Empty `Next` and `Diagnostics` sections render as `(none)`.

Within the diagnostics section, entries are ordered by severity:

1. errors
2. warnings
3. hints

Text diagnostics are human-readable entries that include the diagnostic message rather than bare severity tags. Text error output uses the same section structure and renders on stderr.

## Command-specific data

Each command stores its structured payload under `data`.

- `read`: rendered content metadata and selected lines/section
- `symbol.find`: `matches`
- `symbol.callers`: `callers` and `impact`
- `search.text`: `matches`
- `search.regex`: `matches`
- `files`: `files`
- `deps`: `uses_local`, `uses_external`, `used_by`
- `map`: `entries`, `total_files`

## Maintenance rule

If command names, JSON shape, diagnostics behavior, or text ordering changes, update this file, `README.md`, and the matching integration tests in `tests/` together.
