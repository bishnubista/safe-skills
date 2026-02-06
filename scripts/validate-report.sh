#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <report.md>" >&2
  exit 2
fi

report="$1"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass() {
  echo "[OK] $1"
}

extract_declared_count() {
  local report_path="$1"
  local severity="$2"
  awk -F'|' -v sev="$severity" '
    $0 ~ "^\\| " sev "[[:space:]]+\\|" {
      gsub(/ /, "", $3)
      print $3
      exit
    }
  ' "$report_path"
}

count_findings_in_section() {
  local report_path="$1"
  local section="$2"
  awk -v section="$section" '
    $0 == section {in_section=1; next}
    /^## / && in_section {in_section=0}
    in_section && /^### / {count++}
    END {print count+0}
  ' "$report_path"
}

[[ -f "$report" ]] || fail "report not found: $report"

required_sections=(
  "## Executive Summary"
  "## Critical Findings"
  "## High Findings"
  "## Medium Findings"
  "## Low Findings"
  "## Informational"
  "## Agentic Controls Summary"
  "## Not Applicable"
  "## Remediation Priority"
)

for section in "${required_sections[@]}"; do
  grep -Fq "$section" "$report" || fail "missing section: $section"
done

grep -Eq '^\*\*Scan Type:\*\* (Quick|Full)$' "$report" || fail "missing or invalid Scan Type line"
grep -Eq '^\*\*Scan Scope:\*\* ' "$report" || fail "missing Scan Scope line"

for sev in Critical High Medium Low Info; do
  grep -Eq "^\| ${sev}[[:space:]]+\|[[:space:]]*[0-9]+[[:space:]]*\|$" "$report" || fail "invalid severity row for ${sev}"
done

critical_declared="$(extract_declared_count "$report" "Critical")"
high_declared="$(extract_declared_count "$report" "High")"
medium_declared="$(extract_declared_count "$report" "Medium")"
low_declared="$(extract_declared_count "$report" "Low")"
info_declared="$(extract_declared_count "$report" "Info")"

critical_actual="$(count_findings_in_section "$report" "## Critical Findings")"
high_actual="$(count_findings_in_section "$report" "## High Findings")"
medium_actual="$(count_findings_in_section "$report" "## Medium Findings")"
low_actual="$(count_findings_in_section "$report" "## Low Findings")"
info_actual="$(count_findings_in_section "$report" "## Informational")"

[[ "$critical_declared" == "$critical_actual" ]] || fail "Critical count mismatch (table=$critical_declared, sections=$critical_actual)"
[[ "$high_declared" == "$high_actual" ]] || fail "High count mismatch (table=$high_declared, sections=$high_actual)"
[[ "$medium_declared" == "$medium_actual" ]] || fail "Medium count mismatch (table=$medium_declared, sections=$medium_actual)"
[[ "$low_declared" == "$low_actual" ]] || fail "Low count mismatch (table=$low_declared, sections=$low_actual)"
[[ "$info_declared" == "$info_actual" ]] || fail "Info count mismatch (table=$info_declared, sections=$info_actual)"

has_safe_t_coverage=0
has_legacy_coverage=0
if grep -Fq '## SAFE-T Coverage' "$report"; then
  has_safe_t_coverage=1
fi
if grep -Fq '## Scan Coverage' "$report"; then
  has_legacy_coverage=1
fi

if [[ "$has_safe_t_coverage" -eq 0 && "$has_legacy_coverage" -eq 0 ]]; then
  fail "missing coverage section (expected SAFE-T Coverage or Scan Coverage)"
fi

if [[ "$has_safe_t_coverage" -eq 1 ]]; then
  grep -Eq 'SAFE-T[0-9]{4}' "$report" || fail "SAFE-T coverage section missing technique IDs"
  grep -Fq '## Secondary Framework Rollup' "$report" || fail "missing Secondary Framework Rollup section"
  grep -Eq 'LLM[0-9]{2}|ASI[0-9]{2}|AC0[1-5]' "$report" || fail "secondary mappings missing from SAFE-T report"
fi

if [[ "$has_legacy_coverage" -eq 1 ]]; then
  grep -Fq 'LLM01' "$report" || fail "coverage missing LLM01"
  grep -Fq 'LLM10' "$report" || fail "coverage missing LLM10"
  grep -Fq 'ASI01' "$report" || fail "coverage missing ASI01"
  grep -Fq 'ASI10' "$report" || fail "coverage missing ASI10"
  grep -Fq 'AC01' "$report" || fail "coverage missing AC01"
  grep -Fq 'AC05' "$report" || fail "coverage missing AC05"
fi

if grep -Eq '\{\{[A-Z_]+\}\}' "$report"; then
  fail "unresolved template placeholders found"
fi

pass "$report is structurally valid"
