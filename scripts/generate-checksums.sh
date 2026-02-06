#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_FILE="$ROOT_DIR/CHECKSUMS.sha256"

FILES=(
  .claude-plugin/plugin.json
  .cursor/rules/security-scan.md
  .github/workflows/skill-quality.yml
  commands/scan.md
  skills/claude-code/llm-vulnerability-scan/SKILL.md
  skills/claude-code/llm-vulnerability-scan/references/safe-t-checklist.md
  skills/claude-code/llm-vulnerability-scan/references/owasp-llm-checklist.md
  skills/claude-code/llm-vulnerability-scan/references/agentic-controls.md
  skills/codex/llm-vulnerability-scan/SKILL.md
  skills/codex/llm-vulnerability-scan/agents/openai.yaml
  skills/codex/llm-vulnerability-scan/references/safe-t-checklist.md
  skills/codex/llm-vulnerability-scan/references/owasp-llm-checklist.md
  skills/codex/llm-vulnerability-scan/references/agentic-controls.md
  skills/cursor/llm-vulnerability-scan/security-scan.md
  assets/report-template.md
  scripts/install.sh
  scripts/remote-install.sh
  scripts/generate-checksums.sh
  scripts/lint-skill.sh
  scripts/validate-report.sh
  scripts/parity-smoke.sh
  README.md
)

checksum_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    openssl dgst -sha256 "$1" | awk -v f="$1" '{print $2 "  " f}'
  fi
}

cd "$ROOT_DIR"
: > "$OUT_FILE"

for rel in "${FILES[@]}"; do
  if [[ ! -f "$rel" ]]; then
    echo "ERROR: missing file for checksum manifest: $rel" >&2
    exit 1
  fi
  checksum_cmd "$rel" >> "$OUT_FILE"
done

echo "Wrote $OUT_FILE"
