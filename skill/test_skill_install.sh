#!/usr/bin/env bash
# Test script: verify drail skill installation, discovery, activation, and cleanup
set -euo pipefail

SKILL_SRC="/home/it-dainb/DATA/PROJECTS/drail/skill"
SKILL_DST="$HOME/.claude/skills/drail"

echo "========================================="
echo "  drail Skill Installation Test"
echo "  $(date)"
echo "========================================="
echo ""

# ---- Step 1: Install skill ----
echo "[1/6] Installing skill to $SKILL_DST ..."
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
if [ -d "$SKILL_SRC/references" ]; then
  cp -r "$SKILL_SRC/references" "$SKILL_DST/references"
  echo "  Copied SKILL.md + references/"
else
  echo "  Copied SKILL.md (no references/ dir)"
fi
echo "  OK"
echo ""

# ---- Step 2: Verify files on disk ----
echo "[2/6] Verifying files on disk ..."
if [ -f "$SKILL_DST/SKILL.md" ]; then
  size=$(wc -c < "$SKILL_DST/SKILL.md")
  echo "  SKILL.md exists ($size bytes)"
else
  echo "  FAIL: SKILL.md not found at $SKILL_DST"
  exit 1
fi
if [ -d "$SKILL_DST/references" ]; then
  ref_count=$(find "$SKILL_DST/references" -type f | wc -l)
  echo "  references/ exists ($ref_count files)"
else
  echo "  references/ not present (optional)"
fi
echo "  OK"
echo ""

# ---- Step 3: Check skill discovery via stream-json init ----
echo "[3/6] Checking skill discovery in session init ..."
init_output=$(claude -p "hello" \
  --model haiku --bare \
  --output-format stream-json \
  --allowedTools "Skill" \
  2>/dev/null || echo "{}")

if echo "$init_output" | grep -q '"drail"'; then
  echo "  PASS: 'drail' found in session skills list"
else
  echo "  FAIL: 'drail' NOT in session skills list"
fi
echo ""

# ---- Step 4: Test skill activation (Skill tool must be in allowedTools) ----
echo "[4/6] Testing skill activation with code navigation prompt ..."
echo "  (allowedTools includes Skill — required for activation)"

result=$(claude -p "Find the class PreTrainedModel in the directory /home/it-dainb/DATA/PROJECTS/drail/skill/tests/transformers/src/transformers/ and list its base classes." \
  --model sonnet \
  --output-format stream-json \
  --verbose \
  --permission-mode bypassPermissions \
  --allowedTools "Read,Glob,Grep,Bash,Skill" \
  2>/dev/null || echo "{}")

skill_invocations=$(echo "$result" | grep -o '"name"[[:space:]]*:[[:space:]]*"Skill"' 2>/dev/null | wc -l)
drail_bash_calls=$(echo "$result" | grep -o '"drail ' 2>/dev/null | wc -l)
total_tools=$(echo "$result" | grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' 2>/dev/null | wc -l)

echo "  Total tool calls: $total_tools"
echo "  Skill invocations: $skill_invocations"
echo "  drail via Bash: $drail_bash_calls"

if [ "$skill_invocations" -gt 0 ]; then
  echo "  PASS: Skill tool was invoked (drail loaded)"
else
  echo "  FAIL: Skill tool was NOT invoked"
fi

if [ "$drail_bash_calls" -gt 0 ]; then
  echo "  PASS: drail CLI was used ($drail_bash_calls commands)"
else
  echo "  WARN: drail CLI was not used via Bash"
fi
echo ""

# ---- Step 5: Test WITHOUT Skill tool (should NOT use drail) ----
echo "[5/6] Control test: WITHOUT Skill in allowedTools ..."

result_no_skill=$(claude -p "Find the class PreTrainedModel in the directory /home/it-dainb/DATA/PROJECTS/drail/skill/tests/transformers/src/transformers/ and list its base classes." \
  --model sonnet \
  --output-format stream-json \
  --verbose \
  --permission-mode bypassPermissions \
  --allowedTools "Read,Glob,Grep,Bash" \
  2>/dev/null || echo "{}")

drail_no_skill=$(echo "$result_no_skill" | grep -o '"drail ' 2>/dev/null | wc -l)
total_no_skill=$(echo "$result_no_skill" | grep -o '"type"[[:space:]]*:[[:space:]]*"tool_use"' 2>/dev/null | wc -l)

echo "  Total tool calls: $total_no_skill (without Skill tool)"
echo "  drail via Bash: $drail_no_skill"
if [ "$drail_no_skill" -eq 0 ]; then
  echo "  EXPECTED: drail not used when Skill tool is unavailable"
else
  echo "  UNEXPECTED: drail was used even without Skill tool"
fi
echo ""

# ---- Step 6: Cleanup ----
echo "[6/6] Removing skill from $SKILL_DST ..."
rm -rf "$SKILL_DST"
echo "  Skill removed."
echo ""

# ---- Summary ----
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo ""
if [ "$skill_invocations" -gt 0 ] && [ "$drail_bash_calls" -gt 0 ]; then
  echo "  RESULT: PASS"
  echo "  drail skill installs, gets discovered, loads via Skill tool,"
  echo "  and the model uses drail CLI commands for code navigation."
  echo ""
  echo "  KEY REQUIREMENT: --allowedTools MUST include 'Skill'"
  echo "  for drail to be activated. Without it, skill is visible"
  echo "  but cannot be loaded."
elif [ "$skill_invocations" -gt 0 ]; then
  echo "  RESULT: PARTIAL"
  echo "  Skill loads but model doesn't use drail CLI commands."
  echo "  SKILL.md may need stronger override language."
else
  echo "  RESULT: FAIL"
  echo "  Skill was not activated. Check trigger patterns."
fi
