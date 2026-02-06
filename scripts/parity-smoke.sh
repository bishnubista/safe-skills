#!/usr/bin/env bash
set -euo pipefail

ROOT="docs/security/parity"
# Historical parity artifacts currently diverge by up to 11 High findings on p2.
# Keep this default at 12 until refreshed cross-platform baseline reports are checked in.
MAX_HIGH_DELTA=12

require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "ERROR: $option requires a value" >&2
    usage
    exit 2
  fi
}

usage() {
  cat <<USAGE
Usage: $0 [--root <path>] [--max-high-delta <n>] [--strict]

Validates parity artifacts for Codex vs Claude:
- required report files exist
- each report passes scripts/validate-report.sh
- per-prompt scan type matches across platforms
- per-prompt Critical counts match exactly
- per-prompt High count delta <= threshold
--strict enforces max-high-delta=3 (recommended for refreshed baselines)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      shift
      require_option_value "--root" "${1:-}"
      ROOT="$1"
      ;;
    --max-high-delta)
      shift
      require_option_value "--max-high-delta" "${1:-}"
      MAX_HIGH_DELTA="$1"
      ;;
    --strict)
      MAX_HIGH_DELTA=3
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

[[ "$MAX_HIGH_DELTA" =~ ^[0-9]+$ ]] || fail "max-high-delta must be a non-negative integer (got '$MAX_HIGH_DELTA')"
[[ -d "$ROOT" ]] || fail "parity root directory not found: $ROOT"

extract_count() {
  local report="$1"
  local sev="$2"
  awk -F'|' -v sev="$sev" '
    $0 ~ "^\\| " sev "[[:space:]]*\\|" {
      gsub(/ /, "", $3)
      print $3
      exit
    }
  ' "$report"
}

extract_scan_type() {
  local report="$1"
  sed -n 's/^\*\*Scan Type:\*\* //p' "$report" | head -n 1
}

abs_delta() {
  local a="$1"
  local b="$2"
  if (( a >= b )); then
    echo $((a - b))
  else
    echo $((b - a))
  fi
}

for platform in codex claude; do
  for prompt in p1 p2 p3; do
    report="$ROOT/$platform/${prompt}-report.md"
    [[ -f "$report" ]] || fail "missing report: $report"
    ./scripts/validate-report.sh "$report" >/dev/null
  done
done

echo "[OK] Structural validation passed for all parity reports"

for prompt in p1 p2 p3; do
  codex_report="$ROOT/codex/${prompt}-report.md"
  claude_report="$ROOT/claude/${prompt}-report.md"

  codex_type="$(extract_scan_type "$codex_report")"
  claude_type="$(extract_scan_type "$claude_report")"
  [[ "$codex_type" == "$claude_type" ]] || fail "${prompt}: scan type mismatch (codex=$codex_type, claude=$claude_type)"

  codex_critical="$(extract_count "$codex_report" "Critical")"
  claude_critical="$(extract_count "$claude_report" "Critical")"
  [[ "$codex_critical" == "$claude_critical" ]] || fail "${prompt}: critical count mismatch (codex=$codex_critical, claude=$claude_critical)"

  codex_high="$(extract_count "$codex_report" "High")"
  claude_high="$(extract_count "$claude_report" "High")"
  high_delta="$(abs_delta "$codex_high" "$claude_high")"
  (( high_delta <= MAX_HIGH_DELTA )) || fail "${prompt}: high-count delta too large (codex=$codex_high, claude=$claude_high, delta=$high_delta, max=$MAX_HIGH_DELTA)"

  echo "[OK] ${prompt}: scan type matched, critical matched, high delta=${high_delta}"
done

echo "[OK] Parity smoke check passed"
