#!/usr/bin/env bash
# Update README.md benchmark table from release data
# Reads all skill/release/*/summary.json and rebuilds the table between markers.

set -e

DRAIL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$DRAIL_DIR/README.md"
RELEASE_DIR="$DRAIL_DIR/skill/release"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "No releases found at $RELEASE_DIR"
  exit 0
fi

# Generate table rows from all release summary.json files
TABLE_ROWS=$(python3 -c "
import json, os, glob

release_dir = '$RELEASE_DIR'
rows = []

for summary_path in sorted(glob.glob(os.path.join(release_dir, '*/summary.json'))):
    try:
        with open(summary_path) as f:
            d = json.load(f)

        version = d.get('version', '?')
        prompt_names = d.get('prompt_names', [])
        skill_scores = d.get('skill_scores', {})
        noskill_scores = d.get('noskill_scores', {})
        skill_total = d.get('skill_total', 0)
        noskill_total = d.get('noskill_total', 0)
        skill_tok = d.get('skill_tokens', {})
        noskill_tok = d.get('noskill_tokens', {})
        skill_wall = d.get('skill_wall_seconds', 0)
        noskill_wall = d.get('noskill_wall_seconds', 0)

        short_names = {
            'full_hierarchy': 'Hierarchy',
            'save_model_deep': 'Deep Analysis',
            'three_hop_impact': 'Multi-hop',
            'trainer_comparison': 'Comparison',
            'cross_repo_pattern': 'Cross-repo',
            'dep_graph_analysis': 'Deps',
        }
        ordered = ['full_hierarchy', 'save_model_deep', 'three_hop_impact',
                    'trainer_comparison', 'cross_repo_pattern', 'dep_graph_analysis']

        def fmt_tok(t):
            inp = t.get('input', 0)
            out = t.get('output', 0)
            if inp >= 1000000:
                return f'{inp/1000000:.1f}M / {out/1000:.0f}K'
            elif inp >= 1000:
                return f'{inp/1000:.0f}K / {out/1000:.0f}K'
            return f'{inp} / {out}'

        def fmt_wall(s):
            if s >= 60:
                return f'{s//60}m {s%60}s'
            return f'{s}s'

        # No-skill row
        ns_cells = ' | '.join(str(noskill_scores.get(p, 0)) for p in ordered)
        ns_row = f'| {version} | No Skill | {ns_cells} | **{noskill_total}** | {fmt_tok(noskill_tok)} | {fmt_wall(noskill_wall)} |'
        rows.append(ns_row)

        # Skill row
        s_cells = ' | '.join(str(skill_scores.get(p, 0)) for p in ordered)
        s_row = f'| | **With drail** | {s_cells} | **{skill_total}** | {fmt_tok(skill_tok)} | {fmt_wall(skill_wall)} |'
        rows.append(s_row)

    except Exception as e:
        print(f'<!-- Error reading {summary_path}: {e} -->', flush=True)
        continue

for r in rows:
    print(r)
" 2>/dev/null)

if [ -z "$TABLE_ROWS" ]; then
  echo "No release data to insert."
  exit 0
fi

# Build the full table block
TABLE_BLOCK="<!-- BENCH_TABLE_START -->
| Version | Mode | Hierarchy | Deep Analysis | Multi-hop | Comparison | Cross-repo | Deps | **Total** | Tokens (in/out) | Time |
|---|---|---|---|---|---|---|---|---|---|---|
${TABLE_ROWS}
<!-- BENCH_TABLE_END -->"

# Replace between markers in README
python3 -c "
import re

with open('$README') as f:
    content = f.read()

table = '''$TABLE_BLOCK'''

pattern = r'<!-- BENCH_TABLE_START -->.*?<!-- BENCH_TABLE_END -->'
new_content = re.sub(pattern, table, content, flags=re.DOTALL)

with open('$README', 'w') as f:
    f.write(new_content)
" 2>/dev/null

echo "README.md benchmark table updated."
