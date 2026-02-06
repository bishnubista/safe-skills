#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass() {
  echo "[OK] $1"
}

require_sections() {
  local file="$1"
  shift
  local section
  for section in "$@"; do
    grep -Fq "$section" "$file" || fail "missing section '$section' in $file"
  done
}

required_files=(
  ".claude-plugin/plugin.json"
  ".cursor/rules/security-scan.md"
  "commands/scan.md"
  "skills/claude-code/llm-vulnerability-scan/SKILL.md"
  "skills/claude-code/llm-vulnerability-scan/references/safe-t-checklist.md"
  "skills/claude-code/llm-vulnerability-scan/references/owasp-llm-checklist.md"
  "skills/claude-code/llm-vulnerability-scan/references/agentic-controls.md"
  "skills/codex/llm-vulnerability-scan/SKILL.md"
  "skills/codex/llm-vulnerability-scan/agents/openai.yaml"
  "skills/codex/llm-vulnerability-scan/references/safe-t-checklist.md"
  "skills/codex/llm-vulnerability-scan/references/owasp-llm-checklist.md"
  "skills/codex/llm-vulnerability-scan/references/agentic-controls.md"
  "skills/cursor/llm-vulnerability-scan/security-scan.md"
  "assets/report-template.md"
  "scripts/install.sh"
  "scripts/generate-checksums.sh"
  "scripts/lint-skill.sh"
  "scripts/validate-report.sh"
  "scripts/parity-smoke.sh"
  ".github/workflows/skill-quality.yml"
  "CHECKSUMS.sha256"
)

for path in "${required_files[@]}"; do
  [[ -f "$path" ]] || fail "missing required file: $path"
done

claude_skill="skills/claude-code/llm-vulnerability-scan/SKILL.md"
codex_skill="skills/codex/llm-vulnerability-scan/SKILL.md"
cursor_rule="skills/cursor/llm-vulnerability-scan/security-scan.md"

grep -q '^name: llm-vulnerability-scan$' "$claude_skill" || fail "Claude SKILL name mismatch"
grep -q '^description:' "$claude_skill" || fail "Claude SKILL description missing"
grep -q '^allowed-tools:' "$claude_skill" || fail "Claude SKILL missing allowed-tools"
grep -Fq 'SAFE-T' "$claude_skill" || fail "Claude SKILL missing SAFE-T guidance"

grep -q '^name: llm-vulnerability-scan$' "$codex_skill" || fail "Codex SKILL name mismatch"
grep -q '^description:' "$codex_skill" || fail "Codex SKILL description missing"
grep -Fq 'SAFE-T' "$codex_skill" || fail "Codex SKILL missing SAFE-T guidance"
grep -q '^allowed-tools:' "$codex_skill" && fail "Codex SKILL should not declare allowed-tools"

require_sections "$claude_skill" \
  "## Output" \
  "## Deterministic Rules" \
  "## Phase 1: Discovery" \
  "## Phase 2: Parallel Scan" \
  "## Phase 3: Report Generation"

require_sections "$codex_skill" \
  "## Codex Adapter Notes" \
  "## Output" \
  "## Deterministic Rules" \
  "## Phase 1: Discovery" \
  "## Phase 2: Parallel Scan" \
  "## Phase 3: Report Generation"

grep -Fq 'Cursor is rule-driven' "$cursor_rule" || fail "Cursor rule missing adapter statement"
grep -Fq 'SAFE-T as the primary finding taxonomy' "$cursor_rule" || fail "Cursor rule missing SAFE-T guidance"

cmp -s "$cursor_rule" .cursor/rules/security-scan.md || fail "project Cursor rule is out of sync with cursor adapter"

for ref in safe-t-checklist.md owasp-llm-checklist.md agentic-controls.md; do
  cmp -s "skills/claude-code/llm-vulnerability-scan/references/$ref" "skills/codex/llm-vulnerability-scan/references/$ref" \
    || fail "reference drift between Claude and Codex adapters: $ref"
done

# shellcheck disable=SC2016
grep -Fq '`llm-vulnerability-scan`' commands/scan.md || fail "command does not reference llm-vulnerability-scan"
grep -Fq 'docs/security/llm-vulnerability-report.md' commands/scan.md || fail "command missing report output path"

# shellcheck disable=SC2016
grep -Fq '$llm-vulnerability-scan' skills/codex/llm-vulnerability-scan/agents/openai.yaml || fail "Codex openai adapter default prompt missing skill reference"

grep -Fq '{{SCAN_SCOPE}}' assets/report-template.md || fail "report template missing SCAN_SCOPE placeholder"
grep -Fq '{{SAFE_T_COVERAGE_TABLE}}' assets/report-template.md || fail "report template missing SAFE_T_COVERAGE_TABLE placeholder"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c CHECKSUMS.sha256 >/dev/null || fail "checksum verification failed"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c CHECKSUMS.sha256 >/dev/null || fail "checksum verification failed"
else
  fail "sha256sum or shasum required for checksum verification"
fi

pass "skill lint checks passed"
